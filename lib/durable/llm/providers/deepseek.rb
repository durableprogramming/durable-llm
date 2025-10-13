# frozen_string_literal: true

# DeepSeek provider for language model API access with completion, embedding, and streaming support.

require 'faraday'
require 'json'
require 'event_stream_parser'
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
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
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

        def stream(options)
          opts = options.dup
          opts[:stream] = true
          opts['temperature'] = opts['temperature'].to_f if opts['temperature']

          @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Accept'] = 'text/event-stream'
            req.body = opts
            req.options.on_data = to_json_stream(user_proc: proc { |chunk| yield DeepSeekStreamResponse.new(chunk) })
          end
        end

        private

        # CODE-FROM: ruby-openai @ https://github.com/alexrudall/ruby-openai/blob/main/lib/openai/http.rb
        # MIT License: https://github.com/alexrudall/ruby-openai/blob/main/LICENSE.md
        def to_json_stream(user_proc:)
          parser = EventStreamParser::Parser.new

          proc do |chunk, _bytes, env|
            if env && env.status != 200
              raise_error = Faraday::Response::RaiseError.new
              raise_error.on_complete(env.merge(body: try_parse_json(chunk)))
            end

            parser.feed(chunk) do |_type, data|
              user_proc.call(JSON.parse(data)) unless data == '[DONE]'
            end
          end
        end

        def try_parse_json(maybe_json)
          JSON.parse(maybe_json)
        rescue JSON::ParserError
          maybe_json
        end

        # END-CODE-FROM

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
