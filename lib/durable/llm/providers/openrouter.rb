# frozen_string_literal: true

# OpenRouter provider for accessing various language models through the OpenRouter API.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # OpenRouter provider for accessing various language models through the OpenRouter API.
      # Provides completion, embedding, and streaming capabilities with authentication handling,
      # error management, and response normalization.
      class OpenRouter < Durable::Llm::Providers::Base
        BASE_URL = 'https://openrouter.ai/api/v1'

        def default_api_key
          begin
            Durable::Llm.configuration.openrouter&.api_key
          rescue NoMethodError
            nil
          end || ENV['OPENROUTER_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          super()
          @api_key = api_key || default_api_key
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

          handle_response(response, OpenRouterEmbeddingResponse)
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
            stream.on_chunk { |chunk| block.call(OpenRouterStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        private

        def handle_response(response, response_class = OpenRouterResponse)
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

        # Response wrapper for OpenRouter API completion responses.
        class OpenRouterResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| OpenRouterChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Choice wrapper for OpenRouter API responses.
        class OpenRouterChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = OpenRouterMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Message wrapper for OpenRouter API responses.
        class OpenRouterMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Stream response wrapper for OpenRouter API streaming responses.
        class OpenRouterStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = OpenRouterStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Embedding response wrapper for OpenRouter API embedding responses.
        class OpenRouterEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Stream choice wrapper for OpenRouter API streaming responses.
        class OpenRouterStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = OpenRouterStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Stream delta wrapper for OpenRouter API streaming responses.
        class OpenRouterStreamDelta
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
