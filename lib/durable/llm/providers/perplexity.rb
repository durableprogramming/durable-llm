# frozen_string_literal: true

# This file implements the Perplexity provider for accessing Perplexity's language models through their API,
# providing completion, embedding, and streaming capabilities with authentication handling, error management,
# and response normalization. It establishes HTTP connections to Perplexity's API endpoint, processes chat
# completions and embeddings, handles various API error responses, and includes comprehensive response classes
# to format Perplexity's API responses into a consistent interface.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # The Perplexity provider class for interacting with Perplexity's API.
      #
      # This class provides methods for text completion, embedding generation, streaming responses,
      # and model listing using Perplexity's language models. It handles authentication, HTTP
      # communication, error handling, and response normalization to provide a consistent interface
      # for Perplexity's API services.
      class Perplexity < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.perplexity.ai'

        def default_api_key
          begin
            Durable::Llm.configuration.perplexity&.api_key
          rescue NoMethodError
            nil
          end || ENV['PERPLEXITY_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          super
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, PerplexityEmbeddingResponse)
        end

        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        def self.stream?
          true
        end
        def stream(options, &block)
          options[:stream] = true
          options['temperature'] = options['temperature'].to_f if options['temperature']

          response = @conn.post_stream('chat/completions') do |stream|
            stream.on_chunk { |chunk| block.call(PerplexityStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        private

        def handle_response(response, response_class = PerplexityResponse)
          case response.status
          when 200..299
            response_class.new(response.body)
          when 401
            raise Durable::Llm::AuthenticationError, parse_error_message(response)
          when 429
            raise Durable::Llm::RateLimitError, parse_error_message(response)
          when 400..499
            raise Durable::Llm::InvalidRequestError, parse_error_message(response)
          when 500..599
            raise Durable::Llm::ServerError, parse_error_message(response)
          else
            raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
          end
        end

        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Response class for Perplexity API completion responses.
        #
        # Wraps the raw API response and provides access to choices and data.
        class PerplexityResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| PerplexityChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in a Perplexity completion response.
        #
        # Contains the message and finish reason for the choice.
        class PerplexityChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = PerplexityMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in a Perplexity response.
        #
        # Contains the role and content of the message.
        class PerplexityMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Response class for Perplexity streaming API responses.
        #
        # Wraps streaming chunks and provides access to choices.
        class PerplexityStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = PerplexityStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Response class for Perplexity embedding API responses.
        #
        # Provides access to the embedding vector data.
        class PerplexityEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Represents a single choice in a Perplexity streaming response.
        #
        # Contains the delta and finish reason for the streaming choice.
        class PerplexityStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = PerplexityStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents a delta (incremental content) in a Perplexity streaming response.
        #
        # Contains the role and content delta for streaming updates.
        class PerplexityStreamDelta
          attr_reader :role, :content

          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          def to_s
            @content || ''
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
