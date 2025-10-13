# frozen_string_literal: true

require 'faraday'
require 'json'
require 'event_stream_parser'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Together AI provider for accessing various language models through the Together API.
      #
      # Provides completion, embedding, and streaming capabilities with authentication handling,
      # error management, and response normalization. It establishes HTTP connections to Together's
      # API endpoint, processes chat completions and embeddings, handles various API error responses,
      # and includes comprehensive response classes to format Together's API responses into a
      # consistent interface.
      class Together < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.together.xyz/v1'

        # Returns the default API key for Together AI.
        #
        # @return [String, nil] The API key from configuration or environment variable
        def default_api_key
          begin
            Durable::Llm.configuration.together&.api_key
          rescue NoMethodError
            nil
          end || ENV['TOGETHER_API_KEY']
        end

        attr_accessor :api_key

        # Initializes the Together provider with an API key.
        #
        # @param api_key [String, nil] The API key to use. If nil, uses default_api_key
        def initialize(api_key: nil)
          super
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        # Completes a chat conversation using the Together API.
        #
        # @param options [Hash] The options for the completion request
        # @return [TogetherResponse] The response from the API
        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        # Generates embeddings for the given input using the Together API.
        #
        # @param model [String] The model to use for embedding
        # @param input [String, Array<String>] The input text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @return [TogetherEmbeddingResponse] The embedding response
        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, TogetherEmbeddingResponse)
        end

        # Retrieves the list of available models from the Together API.
        #
        # @return [Array<String>] Array of model IDs
        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        # Indicates whether this provider supports streaming.
        #
        # @return [Boolean] Always true for Together
        def self.stream?
          true
        end

        # Streams a chat completion using the Together API.
        #
        # @param options [Hash] The options for the streaming request
        # @yield [TogetherStreamResponse] Yields stream response chunks
        def stream(options)
          options = prepare_stream_options(options)

          @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Accept'] = 'text/event-stream'
            req.body = options
            req.options.on_data = stream_proc { |chunk| yield TogetherStreamResponse.new(chunk) }
          end
        end

        private

        def prepare_stream_options(options)
          opts = options.dup
          opts[:stream] = true
          opts['temperature'] = opts['temperature'].to_f if opts['temperature']
          opts
        end

        def stream_proc(&block)
          user_proc = proc do |chunk, _size, _total|
            block.call(chunk)
          end
          to_json_stream(user_proc: user_proc)
        end

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

        # Handles the HTTP response and raises appropriate errors or returns the response object.
        #
        # @param response [Faraday::Response] The HTTP response
        # @param response_class [Class] The response class to instantiate (default: TogetherResponse)
        # @return [Object] The response object
        # @raise [Durable::Llm::AuthenticationError] On 401 status
        # @raise [Durable::Llm::RateLimitError] On 429 status
        # @raise [Durable::Llm::InvalidRequestError] On 400-499 status
        # @raise [Durable::Llm::ServerError] On 500-599 status
        # @raise [Durable::Llm::APIError] On other error statuses
        def handle_response(response, response_class = TogetherResponse)
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

        # Parses the error message from the response.
        #
        # @param response [Faraday::Response] The HTTP response
        # @return [String] The formatted error message
        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Response class for Together API completions.
        class TogetherResponse
          attr_reader :raw_response

          # Initializes the response with raw API data.
          #
          # @param response [Hash] The raw response from the API
          def initialize(response)
            @raw_response = response
          end

          # Returns the choices from the response.
          #
          # @return [Array<TogetherChoice>] Array of choices
          def choices
            @raw_response['choices'].map { |choice| TogetherChoice.new(choice) }
          end

          # Returns the data from the response.
          #
          # @return [Array, Hash] The data portion of the response
          def data
            @raw_response['data']
          end

          # Converts the response to a string.
          #
          # @return [String] The concatenated content of all choices
          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a choice in the Together API response.
        class TogetherChoice
          attr_reader :message, :finish_reason

          # Initializes a choice.
          #
          # @param choice [Hash] The choice data
          def initialize(choice)
            @message = TogetherMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          # Converts the choice to string.
          #
          # @return [String] The message content
          def to_s
            @message.to_s
          end
        end

        # Represents a message in the Together API response.
        class TogetherMessage
          attr_reader :role, :content

          # Initializes a message.
          #
          # @param message [Hash] The message data
          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          # Converts to string.
          #
          # @return [String] The content
          def to_s
            @content
          end
        end

        # Response class for streaming Together API responses.
        class TogetherStreamResponse
          attr_reader :choices

          # Initializes the stream response.
          #
          # @param parsed [Hash] The parsed JSON data
          def initialize(parsed)
            @choices = TogetherStreamChoice.new(parsed['choices'])
          end

          # Converts to string.
          #
          # @return [String] The content
          def to_s
            @choices.to_s
          end
        end

        # Response class for Together API embeddings.
        class TogetherEmbeddingResponse
          attr_reader :embedding

          # Initializes the embedding response.
          #
          # @param data [Hash] The raw embedding data
          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          # Returns the embedding as an array.
          #
          # @return [Array<Float>] The embedding vector
          def to_a
            @embedding
          end
        end

        # Represents a choice in streaming responses.
        class TogetherStreamChoice
          attr_reader :delta, :finish_reason

          # Initializes a stream choice.
          #
          # @param choice [Array, Hash] The choice data
          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = TogetherStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          # Converts to string.
          #
          # @return [String] The delta content
          def to_s
            @delta.to_s
          end
        end

        # Represents a delta in streaming responses.
        class TogetherStreamDelta
          attr_reader :role, :content

          # Initializes a stream delta.
          #
          # @param delta [Hash] The delta data
          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          # Converts to string.
          #
          # @return [String] The content or empty string
          def to_s
            @content || ''
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
