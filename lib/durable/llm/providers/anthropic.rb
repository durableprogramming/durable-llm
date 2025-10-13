# frozen_string_literal: true

# Anthropic provider for Claude models with completion and streaming support.

require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'
require 'event_stream_parser'

module Durable
  module Llm
    module Providers
      # Anthropic provider for accessing Claude language models through their API.
      #
      # This provider implements the Durable::Llm::Providers::Base interface to provide
      # completion and streaming capabilities for Anthropic's Claude models including
      # Claude 3.5 Sonnet, Claude 3 Opus, and Claude 3 Haiku. It handles authentication
      # via API keys, supports system messages, and provides comprehensive error handling
      # for various Anthropic API error conditions.
      #
      # Key features:
      # - Message-based chat completions with multi-turn conversations
      # - Real-time streaming responses for interactive applications
      # - System message support for setting context
      # - Automatic model listing from predefined supported models
      # - Comprehensive error handling with specific exception types
      #
      # @example Basic completion
      #   provider = Durable::Llm::Providers::Anthropic.new(api_key: 'your-api-key')
      #   response = provider.completion(
      #     model: 'claude-3-5-sonnet-20240620',
      #     messages: [{ role: 'user', content: 'Hello, world!' }]
      #   )
      #   puts response.choices.first.to_s
      #
      # @example Completion with system message
      #   response = provider.completion(
      #     model: 'claude-3-5-sonnet-20240620',
      #     messages: [
      #       { role: 'system', content: 'You are a helpful assistant.' },
      #       { role: 'user', content: 'Hello!' }
      #     ]
      #   )
      #
      # @example Streaming response
      #   provider.stream(model: 'claude-3-5-sonnet-20240620', messages: messages) do |chunk|
      #     print chunk.to_s
      #   end
      #
      # @see https://docs.anthropic.com/claude/docs/messages-overview Anthropic Messages API Documentation
      class Anthropic < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.anthropic.com'

        # @return [String, nil] The default API key for Anthropic, or nil if not configured
        def default_api_key
          Durable::Llm.configuration.anthropic&.api_key || ENV['ANTHROPIC_API_KEY']
        end

        # @!attribute [rw] api_key
        #   @return [String, nil] The API key used for authentication with Anthropic
        attr_accessor :api_key

        # Initializes a new Anthropic provider instance.
        #
        # @param api_key [String, nil] The Anthropic API key. If nil, uses default_api_key
        # @return [Anthropic] A new Anthropic provider instance
        def initialize(api_key: nil)
          super()
          @api_key = api_key || default_api_key

          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        # Performs a completion request to Anthropic's messages API.
        #
        # @param options [Hash] The completion options
        # @option options [String] :model The Claude model to use
        # @option options [Array<Hash>] :messages Array of message objects with role and content
        # @option options [Integer] :max_tokens Maximum number of tokens to generate (default: 1024)
        # @option options [Float] :temperature Sampling temperature between 0 and 1
        # @option options [String] :system System message to set context
        # @return [AnthropicResponse] The completion response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If Anthropic's servers encounter an error
        def completion(options)
          # Convert symbol keys to strings for consistency
          options = options.transform_keys(&:to_s)

          # Ensure max_tokens is set
          options['max_tokens'] ||= 1024

          # Handle system message separately as Anthropic expects it as a top-level parameter
          system_message = nil
          messages = options['messages']&.dup || []
          if messages.first && (messages.first['role'] || messages.first[:role]) == 'system'
            system_message = messages.first['content'] || messages.first[:content]
            messages = messages[1..] || []
          end

          request_body = options.merge('messages' => messages)
          request_body['system'] = system_message if system_message

          response = @conn.post('/v1/messages') do |req|
            req.headers['x-api-key'] = @api_key
            req.headers['anthropic-version'] = '2023-06-01'
            req.body = request_body
          end

          handle_response(response)
        end

        # Retrieves the list of available models for this provider instance.
        #
        # @return [Array<String>] The list of available Claude model names
        def models
          self.class.models
        end

        # Retrieves the list of supported Claude models.
        #
        # @return [Array<String>] Array of supported Claude model identifiers
        def self.models
          ['claude-3-5-sonnet-20240620', 'claude-3-opus-20240229', 'claude-3-haiku-20240307']
        end

        # @return [Boolean] True, indicating this provider supports streaming
        def self.stream?
          true
        end

        # Performs an embedding request (not supported by Anthropic).
        #
        # @param model [String] The model to use for generating embeddings
        # @param input [String, Array<String>] The input text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @raise [NotImplementedError] Anthropic does not provide embedding APIs
        def embedding(model:, input:, **options)
          raise NotImplementedError, 'Anthropic does not provide embedding APIs'
        end

        # Performs a streaming completion request to Anthropic's messages API.
        #
        # @param options [Hash] The stream options (same as completion plus stream: true)
        # @yield [AnthropicStreamResponse] Yields stream response chunks as they arrive
        # @return [Object] The final response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If Anthropic's servers encounter an error
        def stream(options)
          options = options.transform_keys(&:to_s)
          options['stream'] = true

          # Handle system message separately
          system_message = nil
          messages = options['messages']&.dup || []
          if messages.first && (messages.first['role'] || messages.first[:role]) == 'system'
            system_message = messages.first['content'] || messages.first[:content]
            messages = messages[1..] || []
          end

          request_body = options.merge('messages' => messages)
          request_body['system'] = system_message if system_message

          response = @conn.post('/v1/messages') do |req|
            req.headers['x-api-key'] = @api_key
            req.headers['anthropic-version'] = '2023-06-01'
            req.headers['Accept'] = 'text/event-stream'

            req.body = request_body

            user_proc = proc do |chunk, _size, _total|
              yield AnthropicStreamResponse.new(chunk)
            end

            req.options.on_data = to_json_stream(user_proc: user_proc)
          end

          handle_response(response)
        end

        private

        # Converts JSON stream chunks to individual data objects for processing.
        #
        # This method handles Server-Sent Events from Anthropic's streaming API.
        # It parses the event stream and yields individual JSON objects for each data chunk.
        #
        # @param user_proc [Proc] The proc to call with each parsed JSON object
        # @return [Proc] A proc that can be used as Faraday's on_data callback
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

        # Attempts to parse a string as JSON, returning the string if parsing fails.
        #
        # @param maybe_json [String] The string that might be JSON
        # @return [Hash, Array, String] The parsed JSON object or the original string
        def try_parse_json(maybe_json)
          JSON.parse(maybe_json)
        rescue JSON::ParserError
          maybe_json
        end

        # Processes the API response and handles errors appropriately.
        #
        # @param response [Faraday::Response] The HTTP response from the API
        # @return [AnthropicResponse] An instance of AnthropicResponse for successful responses
        # @raise [Durable::Llm::AuthenticationError] For 401 responses
        # @raise [Durable::Llm::RateLimitError] For 429 responses
        # @raise [Durable::Llm::InvalidRequestError] For 4xx client errors
        # @raise [Durable::Llm::ServerError] For 5xx server errors
        # @raise [Durable::Llm::APIError] For unexpected status codes
        def handle_response(response)
          case response.status
          when 200..299
            AnthropicResponse.new(response.body)
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

        # Extracts and formats error messages from API error responses.
        #
        # @param response [Faraday::Response] The error response from the API
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

        # Response object for Anthropic messages API responses.
        #
        # This class wraps the raw response from Anthropic's messages endpoint
        # and provides a consistent interface for accessing content and metadata.
        class AnthropicResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [AnthropicChoice.new(@raw_response)]
          end

          def usage
            @raw_response['usage']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in an Anthropic messages response.
        #
        # Anthropic typically returns only one choice, containing the assistant's message.
        class AnthropicChoice
          attr_reader :message, :stop_reason

          def initialize(response)
            @message = AnthropicMessage.new(response)
            @stop_reason = response['stop_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in an Anthropic conversation.
        #
        # Messages have a role (user, assistant) and content composed of text blocks.
        class AnthropicMessage
          attr_reader :role, :content

          def initialize(response)
            @role = response['role']
            @content = response['content']&.map { |block| block['text'] }&.join(' ') || ''
          end

          def to_s
            @content
          end
        end

        # Response object for streaming Anthropic messages chunks.
        #
        # This wraps individual chunks from the Server-Sent Events stream,
        # providing access to the incremental content updates.
        class AnthropicStreamResponse
          attr_reader :choices, :type

          def initialize(parsed)
            @type = parsed['type']
            @choices = case @type
                       when 'content_block_delta'
                         [AnthropicStreamChoice.new(parsed)]
                       else
                         []
                       end
          end

          def to_s
            @choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in a streaming Anthropic response chunk.
        #
        # Contains the delta (incremental content) for the choice.
        class AnthropicStreamChoice
          attr_reader :delta

          def initialize(event)
            @delta = AnthropicStreamDelta.new(event['delta'])
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the type and text content of the delta.
        class AnthropicStreamDelta
          attr_reader :type, :text

          def initialize(delta)
            @type = delta['type']
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
