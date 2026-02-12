# frozen_string_literal: true

# DeepSeek provider for language model API access with completion, embedding, and streaming support.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # DeepSeek provider for language model API interactions
      class DeepSeek < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.deepseek.com'

        def default_api_key
          Durable::Llm.configuration.deepseek&.api_key || ENV['DEEPSEEK_API_KEY']
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

          handle_response(response, DeepSeekEmbeddingResponse)
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
          opts = options.dup
          opts[:stream] = true
          opts['temperature'] = opts['temperature'].to_f if opts['temperature']

          response = @conn.post_stream('chat/completions') do |stream|
            stream.on_chunk { |chunk| block.call(DeepSeekStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = opts
          end

          handle_response(response)
        end

        private

        def handle_response(response, response_class = DeepSeekResponse)
          case response.status
          when 200..299 then response_class.new(response.body)
          when 401 then raise Durable::Llm::AuthenticationError, parse_error_message(response)
          when 429 then raise Durable::Llm::RateLimitError, parse_error_message(response)
          when 400..499 then raise Durable::Llm::InvalidRequestError, parse_error_message(response)
          when 500..599 then raise Durable::Llm::ServerError, parse_error_message(response)
          else raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
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

        # Response wrapper for DeepSeek API responses
        class DeepSeekResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| DeepSeekChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Choice wrapper for DeepSeek response choices
        class DeepSeekChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = DeepSeekMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Message wrapper for DeepSeek messages
        class DeepSeekMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Stream response wrapper for DeepSeek streaming
        class DeepSeekStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = DeepSeekStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Embedding response wrapper for DeepSeek embeddings
        class DeepSeekEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Stream choice wrapper for DeepSeek streaming
        class DeepSeekStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = DeepSeekStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Stream delta wrapper for DeepSeek streaming
        class DeepSeekStreamDelta
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
