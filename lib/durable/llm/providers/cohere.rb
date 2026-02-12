# frozen_string_literal: true

# This file implements the Cohere provider for accessing Cohere's language models through their API.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Cohere provider for accessing Cohere's language models
      #
      # This class provides completion, embedding, and streaming capabilities
      # for Cohere's API, including proper error handling and response normalization.
      class Cohere < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.cohere.ai/v2'

        def default_api_key
          Durable::Llm.configuration.cohere&.api_key || ENV['COHERE_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          super(api_key: api_key)
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        def completion(options)
          response = @conn.post('chat') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Content-Type'] = 'application/json'
            req.body = options
          end

          handle_response(response)
        end
        def stream(options, &block)
          options[:stream] = true

          response = @conn.post_stream('chat') do |stream|
            stream.on_chunk { |chunk| block.call(CohereStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = @conn.post('embed') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Content-Type'] = 'application/json'
            req.body = { model: model, texts: Array(input), input_type: 'search_document', **options }
          end

          handle_response(response, CohereEmbeddingResponse)
        end

        def models
          response = @conn.get('../v1/models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          data = handle_response(response).raw_response
          data['models']&.map { |model| model['name'] }
        end

        def self.stream?
          true
        end

        private

        def handle_response(response, response_class = CohereResponse)
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
          message = body&.dig('message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Response object for Cohere chat API responses.
        #
        # Wraps the raw response and provides a consistent interface for accessing
        # message content and metadata.
        class CohereResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response.dig('message', 'content')&.map { |generation| CohereChoice.new(generation) } || []
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in a Cohere response.
        #
        # Contains the generated text content.
        class CohereChoice
          attr_reader :text

          def initialize(generation)
            @text = generation['text']
          end

          def to_s
            @text
          end
        end

        # Response object for Cohere embedding API responses.
        #
        # Wraps embedding data and provides array access to the vector representation.
        class CohereEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('embeddings', 'float', 0)
          end

          def to_a
            @embedding
          end
        end

        # Response object for streaming Cohere chat chunks.
        #
        # Wraps individual chunks from the Server-Sent Events stream.
        class CohereStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = [CohereStreamChoice.new(parsed['delta'])]
          end

          def to_s
            @choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in a streaming Cohere response chunk.
        #
        # Contains the delta (incremental content) for the choice.
        class CohereStreamChoice
          attr_reader :delta

          def initialize(delta)
            @delta = CohereStreamDelta.new(delta)
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the text content of the delta.
        class CohereStreamDelta
          attr_reader :text

          def initialize(delta)
            @text = delta['text']
          end

          def to_s
            @text || ''
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
