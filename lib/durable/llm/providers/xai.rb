# frozen_string_literal: true

# This file implements the xAI provider for accessing xAI's Grok language models through their API,
# providing completion, embedding, and streaming capabilities with authentication handling, error management,
# and response normalization. It establishes HTTP connections to xAI's API endpoint, processes chat completions
# and embeddings, handles various API error responses, and includes comprehensive response classes to format
# xAI's API responses into a consistent interface.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # xAI provider for accessing xAI's Grok language models.
      #
      # This class provides methods to interact with xAI's API for chat completions,
      # embeddings, model listing, and streaming responses.
      class Xai < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.x.ai/v1'

        # Returns the default API key for xAI, checking configuration and environment variables.
        #
        # @return [String, nil] The API key or nil if not found
        def default_api_key
          begin
            Durable::Llm.configuration.xai&.api_key
          rescue NoMethodError
            nil
          end || ENV['XAI_API_KEY']
        end

        attr_accessor :api_key

        # Initializes the xAI provider with API key and HTTP connection.
        #
        # @param api_key [String, nil] The API key to use, defaults to default_api_key
        def initialize(api_key: nil)
          super
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        # Performs a chat completion request to xAI's API.
        #
        # @param options [Hash] The completion options including model, messages, etc.
        # @return [XaiResponse] The parsed response from xAI
        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        # Performs an embedding request to xAI's API.
        #
        # @param model [String] The embedding model to use
        # @param input [String, Array<String>] The text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @return [XaiEmbeddingResponse] The parsed embedding response
        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, XaiEmbeddingResponse)
        end

        # Retrieves the list of available models from xAI's API.
        #
        # @return [Array<String>] Array of model IDs
        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        # Indicates whether this provider supports streaming responses.
        #
        # @return [Boolean] Always true for xAI provider
        def self.stream?
          true
        end

        # Performs a streaming chat completion request to xAI's API.
        #
        # @param options [Hash] The completion options including model, messages, etc.
        # @yield [XaiStreamResponse] Yields each chunk of the streaming response
        # @return [nil] Returns after streaming is complete
        def stream(options, &block)
          options[:stream] = true
          options['temperature'] = options['temperature'].to_f if options['temperature']

          response = @conn.post_stream('chat/completions') do |stream|
            stream.on_chunk { |chunk| block.call(XaiStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        private

        # Handles HTTP responses from xAI's API, raising appropriate errors or returning parsed responses.
        #
        # @param response [Faraday::Response] The HTTP response
        # @param response_class [Class] The response class to instantiate for successful responses
        # @return [Object] The parsed response object
        # @raise [Durable::Llm::AuthenticationError] For 401 responses
        # @raise [Durable::Llm::RateLimitError] For 429 responses
        # @raise [Durable::Llm::InvalidRequestError] For 400-499 responses
        # @raise [Durable::Llm::ServerError] For 500-599 responses
        # @raise [Durable::Llm::APIError] For unexpected status codes
        def handle_response(response, response_class = XaiResponse)
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

        # Parses error messages from xAI API responses.
        #
        # @param response [Faraday::Response] The HTTP response
        # @return [String] Formatted error message
        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Represents a response from xAI's chat completion API.
        class XaiResponse
          attr_reader :raw_response

          # Initializes the response with raw API data.
          #
          # @param response [Hash] The parsed JSON response from xAI
          def initialize(response)
            @raw_response = response
          end

          # Returns the choices from the response.
          #
          # @return [Array<XaiChoice>] Array of choice objects
          def choices
            @raw_response['choices'].map { |choice| XaiChoice.new(choice) }
          end

          # Returns the data field from the response.
          #
          # @return [Array, nil] The data array or nil
          def data
            @raw_response['data']
          end

          # Converts the response to a string by joining all choice messages.
          #
          # @return [String] The concatenated response text
          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in an xAI response.
        class XaiChoice
          attr_reader :message, :finish_reason

          # Initializes the choice with message and finish reason.
          #
          # @param choice [Hash] The choice data from the API response
          def initialize(choice)
            @message = XaiMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          # Converts the choice to a string by returning the message content.
          #
          # @return [String] The message content
          def to_s
            @message.to_s
          end
        end

        # Represents a message in an xAI response.
        class XaiMessage
          attr_reader :role, :content

          # Initializes the message with role and content.
          #
          # @param message [Hash] The message data from the API response
          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          # Converts the message to a string by returning the content.
          #
          # @return [String] The message content
          def to_s
            @content
          end
        end

        # Represents a streaming response chunk from xAI's API.
        class XaiStreamResponse
          attr_reader :choices

          # Initializes the stream response with parsed chunk data.
          #
          # @param parsed [Hash] The parsed JSON chunk from the stream
          def initialize(parsed)
            @choices = XaiStreamChoice.new(parsed['choices'])
          end

          # Converts the stream response to a string by returning the choice content.
          #
          # @return [String] The chunk content
          def to_s
            @choices.to_s
          end
        end

        # Represents an embedding response from xAI's API.
        class XaiEmbeddingResponse
          attr_reader :embedding

          # Initializes the embedding response with the embedding data.
          #
          # @param data [Hash] The parsed JSON response containing embeddings
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

        # Represents a choice in a streaming response from xAI.
        class XaiStreamChoice
          attr_reader :delta, :finish_reason

          # Initializes the stream choice with delta and finish reason.
          #
          # @param choice [Array, Hash] The choice data from the stream chunk
          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = XaiStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          # Converts the choice to a string by returning the delta content.
          #
          # @return [String] The delta content
          def to_s
            @delta.to_s
          end
        end

        # Represents a delta (incremental change) in a streaming response.
        class XaiStreamDelta
          attr_reader :role, :content

          # Initializes the delta with role and content.
          #
          # @param delta [Hash] The delta data from the stream chunk
          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          # Converts the delta to a string by returning the content or empty string.
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
