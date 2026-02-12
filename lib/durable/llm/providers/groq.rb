# frozen_string_literal: true

# Groq provider for OpenAI-compatible API access.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Groq provider for accessing language models via OpenAI-compatible API.
      #
      # Provides completion, embedding, and streaming capabilities with proper
      # error handling and response normalization.
      class Groq < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.groq.com/openai/v1'

        def default_api_key
          Durable::Llm.configuration.groq&.api_key || ENV['GROQ_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          super
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        attr_reader :conn

        def completion(options)
          response = conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, GroqEmbeddingResponse)
        end

        def models
          response = conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          resp = handle_response(response).to_h

          resp['data'].map { |model| model['id'] }
        end

        def self.stream?
          true
        end

        def stream(options, &block)
          options[:stream] = true
          options['temperature'] = options['temperature'].to_f if options['temperature']

          response = conn.post_stream('chat/completions') do |stream|
            stream.on_chunk { |chunk| block.call(GroqStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        private

        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        def handle_response(response, response_class = GroqResponse)
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

        # Response object for Groq chat API responses.
        #
        # Wraps the raw response and provides a consistent interface for accessing
        # message content, embeddings, and metadata.
        class GroqResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| GroqChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def embedding
            @raw_response.dig('data', 0, 'embedding')
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end

          def to_h
            @raw_response.dup
          end
        end

        # Represents a single choice in a Groq response.
        #
        # Contains the message and finish reason for the choice.
        class GroqChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = GroqMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in a Groq conversation.
        #
        # Messages have a role (user, assistant, system) and text content.
        class GroqMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Response object for streaming Groq chat chunks.
        #
        # Wraps individual chunks from the Server-Sent Events stream.
        class GroqStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = GroqStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Represents a single choice in a streaming Groq response chunk.
        #
        # Contains the delta (incremental content) and finish reason for the choice.
        class GroqStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = GroqStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the role and text content of the delta.
        class GroqStreamDelta
          attr_reader :role, :content

          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          def to_s
            @content || ''
          end
        end

        # Response object for Groq embedding API responses.
        #
        # Wraps embedding data and provides array access to the vector representation.
        class GroqEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
