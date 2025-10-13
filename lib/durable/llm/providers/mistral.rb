# frozen_string_literal: true

# Mistral AI provider for language models with completion, embedding, and streaming support.
# Handles authentication, HTTP connections, error management, and response normalization.

require 'faraday'
require 'json'
require 'event_stream_parser'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Mistral AI provider for accessing Mistral AI's language models
      #
      # This class provides a complete interface to Mistral AI's API, supporting
      # text completions, embeddings, model listing, and streaming responses.
      # It handles authentication, HTTP communication, error management, and
      # response normalization to provide a consistent API experience.
      #
      # @example Basic usage
      #   provider = Durable::Llm::Providers::Mistral.new(api_key: 'your_key')
      #   response = provider.completion(model: 'mistral-medium', messages: [{role: 'user', content: 'Hello'}])
      #   puts response.choices.first.to_s
      #
      # @example Streaming responses
      #   provider.stream(model: 'mistral-medium', messages: [{role: 'user', content: 'Tell a story'}]) do |chunk|
      #     print chunk.to_s
      #   end
      class Mistral < Durable::Llm::Providers::Base
        # Base URL for Mistral AI API
        BASE_URL = 'https://api.mistral.ai/v1'

        # Returns the default API key for Mistral AI
        #
        # Checks the configuration object first, then falls back to the MISTRAL_API_KEY environment variable.
        #
        # @return [String, nil] The default API key, or nil if not configured
        def default_api_key
          begin
            Durable::Llm.configuration.mistral&.api_key
          rescue NoMethodError
            nil
          end || ENV['MISTRAL_API_KEY']
        end

        # @!attribute [rw] api_key
        #   @return [String, nil] The API key used for Mistral AI authentication
        attr_accessor :api_key

        # Initializes a new Mistral provider instance
        #
        # @param api_key [String, nil] The API key for Mistral AI. If not provided, uses default_api_key
        def initialize(api_key: nil)
          super()
          @api_key = api_key || default_api_key
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        # Performs a chat completion request to Mistral AI
        #
        # @param options [Hash] The completion options
        # @option options [String] :model The model to use (e.g., 'mistral-medium', 'mistral-small')
        # @option options [Array<Hash>] :messages Array of message objects with :role and :content
        # @option options [Float] :temperature (optional) Controls randomness (0.0 to 1.0)
        # @option options [Integer] :max_tokens (optional) Maximum tokens to generate
        # @return [MistralResponse] The completion response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If Mistral AI servers encounter an error
        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        # Generates embeddings for the given input text
        #
        # @param model [String] The embedding model to use (e.g., 'mistral-embed')
        # @param input [String, Array<String>] The text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @return [MistralEmbeddingResponse] The embedding response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If Mistral AI servers encounter an error
        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, MistralEmbeddingResponse)
        end

        # Retrieves the list of available models from Mistral AI
        #
        # @return [Array<String>] Array of available model identifiers
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::ServerError] If Mistral AI servers encounter an error
        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        # Indicates whether this provider supports streaming responses
        #
        # @return [Boolean] Always returns true for Mistral provider
        def self.stream?
          true
        end

        # Performs a streaming chat completion request to Mistral AI
        #
        # Yields response chunks as they arrive from the API.
        #
        # @param options [Hash] The stream options (same as completion plus :stream => true)
        # @yield [MistralStreamResponse] Each streaming response chunk
        # @return [nil] Returns nil after streaming is complete
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If Mistral AI servers encounter an error
        def stream(options)
          options[:stream] = true

          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Accept'] = 'text/event-stream'

            options['temperature'] = options['temperature'].to_f if options['temperature']

            req.body = options

            user_proc = proc do |chunk, _size, _total|
              yield MistralStreamResponse.new(chunk)
            end

            req.options.on_data = to_json_stream(user_proc: user_proc)
          end

          handle_response(response)
        end

        private

        # CODE-FROM: ruby-openai @ https://github.com/alexrudall/ruby-openai/blob/main/lib/openai/http.rb
        # MIT License: https://github.com/alexrudall/ruby-openai/blob/main/LICENSE.md

        # Creates a proc for processing JSON streaming responses
        #
        # @param user_proc [Proc] The proc to call with each parsed JSON chunk
        # @return [Proc] A proc that handles raw streaming data and parses it as JSON
        # @private
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

        # Attempts to parse a string as JSON, returning the string if parsing fails
        #
        # @param maybe_json [String] The string that might be JSON
        # @return [Hash, Array, String] Parsed JSON object or original string if parsing failed
        # @private
        def try_parse_json(maybe_json)
          JSON.parse(maybe_json)
        rescue JSON::ParserError
          maybe_json
        end

        # END-CODE-FROM

        # Processes the HTTP response and handles errors or returns normalized response
        #
        # @param response [Faraday::Response] The HTTP response from the API
        # @param response_class [Class] The response class to instantiate for successful responses
        # @return [Object] Instance of response_class for successful responses
        # @raise [Durable::Llm::AuthenticationError] For 401 responses
        # @raise [Durable::Llm::RateLimitError] For 429 responses
        # @raise [Durable::Llm::InvalidRequestError] For 4xx responses
        # @raise [Durable::Llm::ServerError] For 5xx responses
        # @raise [Durable::Llm::APIError] For unexpected response codes
        # @private
        def handle_response(response, response_class = MistralResponse)
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

        # Extracts error message from API response
        #
        # @param response [Faraday::Response] The HTTP response containing error information
        # @return [String] The formatted error message
        # @private
        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Response object for Mistral AI completion API responses
        #
        # Wraps the raw API response and provides convenient access to choices and data.
        class MistralResponse
          # @!attribute [r] raw_response
          #   @return [Hash] The raw response data from Mistral AI API
          attr_reader :raw_response

          # Initializes a new response object
          #
          # @param response [Hash] The raw API response data
          def initialize(response)
            @raw_response = response
          end

          # Returns the completion choices from the response
          #
          # @return [Array<MistralChoice>] Array of choice objects
          def choices
            @raw_response['choices'].map { |choice| MistralChoice.new(choice) }
          end

          # Returns the raw data array from the response
          #
          # @return [Array] The data array from the API response
          def data
            @raw_response['data']
          end

          # Returns the concatenated text of all choices
          #
          # @return [String] The combined text content of all choices
          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single completion choice from Mistral AI
        #
        # Contains the message content and finish reason for a completion choice.
        class MistralChoice
          # @!attribute [r] message
          #   @return [MistralMessage] The message object for this choice
          # @!attribute [r] finish_reason
          #   @return [String] The reason the completion finished (e.g., 'stop', 'length')
          attr_reader :message, :finish_reason

          # Initializes a new choice object
          #
          # @param choice [Hash] The raw choice data from the API response
          def initialize(choice)
            @message = MistralMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          # Returns the text content of the message
          #
          # @return [String] The message content
          def to_s
            @message.to_s
          end
        end

        # Represents a chat message in Mistral AI conversations
        #
        # Contains the role (user/assistant/system) and content of a message.
        class MistralMessage
          # @!attribute [r] role
          #   @return [String] The role of the message sender ('user', 'assistant', or 'system')
          # @!attribute [r] content
          #   @return [String] The text content of the message
          attr_reader :role, :content

          # Initializes a new message object
          #
          # @param message [Hash] The raw message data from the API
          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          # Returns the message content
          #
          # @return [String] The text content of the message
          def to_s
            @content
          end
        end

        # Response object for streaming Mistral AI API responses
        #
        # Wraps streaming response chunks and provides access to streaming choices.
        class MistralStreamResponse
          # @!attribute [r] choices
          #   @return [MistralStreamChoice] The streaming choice object
          attr_reader :choices

          # Initializes a new streaming response object
          #
          # @param parsed [Hash] The parsed streaming response data
          def initialize(parsed)
            @choices = MistralStreamChoice.new(parsed['choices'])
          end

          # Returns the text content of the streaming response
          #
          # @return [String] The text content from the streaming choice
          def to_s
            @choices.to_s
          end
        end

        # Response object for Mistral AI embedding API responses
        #
        # Contains the embedding vector data from Mistral AI's embedding models.
        class MistralEmbeddingResponse
          # @!attribute [r] embedding
          #   @return [Array<Float>] The embedding vector
          attr_reader :embedding

          # Initializes a new embedding response object
          #
          # @param data [Hash] The raw embedding response data from the API
          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          # Returns the embedding as an array
          #
          # @return [Array<Float>] The embedding vector
          def to_a
            @embedding
          end
        end

        # Represents a streaming choice from Mistral AI
        #
        # Contains delta content and finish reason for streaming completions.
        class MistralStreamChoice
          # @!attribute [r] delta
          #   @return [MistralStreamDelta] The delta content for this streaming choice
          # @!attribute [r] finish_reason
          #   @return [String, nil] The reason the stream finished, or nil if still streaming
          attr_reader :delta, :finish_reason

          # Initializes a new streaming choice object
          #
          # @param choice [Array<Hash>, Hash] The raw streaming choice data
          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = MistralStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          # Returns the text content of the delta
          #
          # @return [String] The delta content
          def to_s
            @delta.to_s
          end
        end

        # Represents a delta (incremental change) in streaming responses
        #
        # Contains incremental content and role information for streaming completions.
        class MistralStreamDelta
          # @!attribute [r] role
          #   @return [String, nil] The role for this delta, or nil if not present
          # @!attribute [r] content
          #   @return [String, nil] The incremental content, or nil if not present
          attr_reader :role, :content

          # Initializes a new stream delta object
          #
          # @param delta [Hash] The raw delta data from the streaming response
          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          # Returns the content of the delta, or empty string if none
          #
          # @return [String] The delta content or empty string
          def to_s
            @content || ''
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
