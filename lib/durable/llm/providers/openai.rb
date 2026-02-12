# frozen_string_literal: true

# This file implements the OpenAI provider for accessing OpenAI's language models through their API, providing completion, embedding, and streaming capabilities with authentication handling, error management, and response normalization. It establishes HTTP connections to OpenAI's v1 API endpoint, processes chat completions and embeddings with organization support, handles various API error responses including rate limiting and authentication errors, and includes comprehensive response classes to format OpenAI's API responses into a consistent interface. The provider supports both regular and streaming response modes using event stream parsing for real-time token streaming, and includes specialized handling for embedding responses alongside standard chat completion functionality.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # OpenAI provider for accessing OpenAI's language models through their API.
      #
      # This provider implements the Durable::Llm::Providers::Base interface to provide
      # completion, embedding, and streaming capabilities for OpenAI's models including
      # GPT-3.5, GPT-4, and their variants. It handles authentication via API keys,
      # supports organization-based access, and provides comprehensive error handling
      # for various OpenAI API error conditions.
      #
      # Key features:
      # - Chat completions with support for multi-turn conversations
      # - Text embeddings for semantic similarity and retrieval tasks
      # - Real-time streaming responses for interactive applications
      # - Automatic model listing from OpenAI's API
      # - Organization support for enterprise accounts
      # - Comprehensive error handling with specific exception types
      #
      # @example Basic completion
      #   provider = Durable::Llm::Providers::OpenAI.new(api_key: 'your-api-key')
      #   response = provider.completion(
      #     model: 'gpt-3.5-turbo',
      #     messages: [{ role: 'user', content: 'Hello, world!' }]
      #   )
      #   puts response.choices.first.to_s
      #
      # @example Streaming response
      #   provider.stream(model: 'gpt-4', messages: messages) do |chunk|
      #     print chunk.to_s
      #   end
      #
      # @example Text embedding
      #   embedding = provider.embedding(
      #     model: 'text-embedding-ada-002',
      #     input: 'Some text to embed'
      #   )
      #
      # @see https://platform.openai.com/docs/api-reference OpenAI API Documentation
      class OpenAI < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.openai.com/v1'

        def default_api_key
          begin
            Durable::Llm.configuration.openai&.api_key
          rescue NoMethodError
            nil
          end || ENV['OPENAI_API_KEY']
        end

        # @!attribute [rw] api_key
        #   @return [String, nil] The API key used for authentication with OpenAI
        # @!attribute [rw] organization
        #   @return [String, nil] The OpenAI organization ID for enterprise accounts
        attr_accessor :api_key, :organization

        # Initializes a new OpenAI provider instance.
        #
        # @param api_key [String, nil] The OpenAI API key. If nil, uses default_api_key
        # @param organization [String, nil] The OpenAI organization ID. If nil, uses ENV['OPENAI_ORGANIZATION']
        # @return [OpenAI] A new OpenAI provider instance
        def initialize(api_key: nil, organization: nil)
          super(api_key: api_key)
          @organization = organization || ENV['OPENAI_ORGANIZATION']
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        # Performs a chat completion request to OpenAI's API.
        #
        # @param options [Hash] The completion options
        # @option options [String] :model The model to use (e.g., 'gpt-3.5-turbo', 'gpt-4')
        # @option options [Array<Hash>] :messages Array of message objects with role and content
        # @option options [Float] :temperature Sampling temperature between 0 and 2
        # @option options [Integer] :max_tokens Maximum number of tokens to generate
        # @option options [Float] :top_p Nucleus sampling parameter
        # @return [OpenAIResponse] The completion response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If OpenAI's servers encounter an error
        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
            req.body = options
          end

          handle_response(response)
        end

        # Performs an embedding request to OpenAI's API.
        #
        # @param model [String] The embedding model to use (e.g., 'text-embedding-ada-002')
        # @param input [String, Array<String>] The text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @return [OpenAIEmbeddingResponse] The embedding response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If OpenAI's servers encounter an error
        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, OpenAIEmbeddingResponse)
        end

        # Retrieves the list of available models from OpenAI's API.
        #
        # @return [Array<String>] Array of model IDs available to the account
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::ServerError] If OpenAI's servers encounter an error
        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        # @return [Boolean] True, indicating this provider supports streaming
        def self.stream?
          true
        end

        # Performs a streaming chat completion request to OpenAI's API.
        #
        # @param options [Hash] The stream options (same as completion plus stream: true)
        # @yield [OpenAIStreamResponse] Yields stream response chunks as they arrive
        # @return [Object] The final response object
        # @raise [Durable::Llm::AuthenticationError] If API key is invalid
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded
        # @raise [Durable::Llm::InvalidRequestError] If request parameters are invalid
        # @raise [Durable::Llm::ServerError] If OpenAI's servers encounter an error
        def stream(options, &block)
          options[:stream] = true
          options['temperature'] = options['temperature'].to_f if options['temperature']

          response = @conn.post_stream('chat/completions') do |stream|
            stream.on_chunk { |chunk| block.call(OpenAIStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['OpenAI-Organization'] = @organization if @organization
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        private

        # Processes the API response and handles errors appropriately.
        #
        # @param response [Faraday::Response] The HTTP response from the API
        # @param response_class [Class] The response class to instantiate for successful responses
        # @return [Object] An instance of response_class for successful responses
        # @raise [Durable::Llm::AuthenticationError] For 401 responses
        # @raise [Durable::Llm::RateLimitError] For 429 responses
        # @raise [Durable::Llm::InvalidRequestError] For 4xx client errors
        # @raise [Durable::Llm::ServerError] For 5xx server errors
        # @raise [Durable::Llm::APIError] For unexpected status codes
        def handle_response(response, response_class = OpenAIResponse)
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

        # Response object for OpenAI chat completion API responses.
        #
        # This class wraps the raw response from OpenAI's chat completions endpoint
        # and provides a consistent interface for accessing choices, usage data, and
        # other response components.
        class OpenAIResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| OpenAIChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def embedding
            @raw_response['embedding']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in an OpenAI chat completion response.
        #
        # Each choice contains a message with role and content, along with
        # metadata like finish reason.
        class OpenAIChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = OpenAIMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in an OpenAI chat completion.
        #
        # Messages have a role (system, user, assistant) and content text.
        class OpenAIMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Response object for streaming OpenAI chat completion chunks.
        #
        # This wraps individual chunks from the Server-Sent Events stream,
        # providing access to the incremental content updates.
        class OpenAIStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = OpenAIStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Response object for OpenAI embedding API responses.
        #
        # Provides access to the embedding vectors generated for input text.
        class OpenAIEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Represents a single choice in a streaming OpenAI response chunk.
        #
        # Contains the delta (incremental content) and finish reason for the choice.
        class OpenAIStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = OpenAIStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the role (for the first chunk) and content updates.
        class OpenAIStreamDelta
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
