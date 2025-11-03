# frozen_string_literal: true

# This file implements the Fireworks AI provider for accessing Fireworks AI's language models through their API, providing completion, embedding, and streaming capabilities with authentication handling, error management, and response normalization. It establishes HTTP connections to Fireworks AI's API endpoint, processes chat completions and embeddings, handles various API error responses, and includes comprehensive response classes to format Fireworks AI's API responses into a consistent interface.

require 'faraday'
require 'json'
require 'event_stream_parser'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Fireworks AI provider for accessing Fireworks AI's language models.
      #
      # Provides completion, embedding, and streaming capabilities with proper
      # error handling and response normalization.
      class Fireworks < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.fireworks.ai/inference/v1'

        def default_api_key
          Durable::Llm.configuration.fireworks&.api_key || ENV['FIREWORKS_API_KEY']
        end

        attr_accessor :api_key

        # Initializes a new Fireworks provider instance.
        #
        # @param api_key [String, nil] The API key for Fireworks AI. If not provided, uses the default from configuration or environment.
        # @return [Fireworks] A new instance of the Fireworks provider.
        def initialize(api_key: nil)
          super()
          @api_key = api_key || default_api_key
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        # Performs a chat completion request to Fireworks AI.
        #
        # @param options [Hash] The completion options including model, messages, temperature, etc.
        # @return [FireworksResponse] The response object containing the completion results.
        # @raise [Durable::Llm::AuthenticationError] If authentication fails.
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded.
        # @raise [Durable::Llm::InvalidRequestError] If the request is invalid.
        # @raise [Durable::Llm::ServerError] If there's a server error.
        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        # Generates embeddings for the given input using Fireworks AI.
        #
        # @param model [String] The model to use for generating embeddings.
        # @param input [String, Array<String>] The text input(s) to embed.
        # @param options [Hash] Additional options for the embedding request.
        # @return [FireworksEmbeddingResponse] The response object containing the embeddings.
        # @raise [Durable::Llm::AuthenticationError] If authentication fails.
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded.
        # @raise [Durable::Llm::InvalidRequestError] If the request is invalid.
        # @raise [Durable::Llm::ServerError] If there's a server error.
        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, FireworksEmbeddingResponse)
        end

        # Retrieves the list of available models from Fireworks AI.
        #
        # @return [Array<String>] An array of model IDs available for use.
        # @raise [Durable::Llm::AuthenticationError] If authentication fails.
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded.
        # @raise [Durable::Llm::InvalidRequestError] If the request is invalid.
        # @raise [Durable::Llm::ServerError] If there's a server error.
        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        def self.stream?
          true
        end

        # Performs a streaming chat completion request to Fireworks AI.
        #
        # @param options [Hash] The completion options including model, messages, temperature, etc.
        # @yield [FireworksStreamResponse] Yields each chunk of the streaming response.
        # @return [nil] Returns nil after streaming is complete.
        # @raise [Durable::Llm::AuthenticationError] If authentication fails.
        # @raise [Durable::Llm::RateLimitError] If rate limit is exceeded.
        # @raise [Durable::Llm::InvalidRequestError] If the request is invalid.
        # @raise [Durable::Llm::ServerError] If there's a server error.
        def stream(options)
          options[:stream] = true

          @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Accept'] = 'text/event-stream'

            options['temperature'] = options['temperature'].to_f if options['temperature']

            req.body = options

            user_proc = proc do |chunk, _size, _total|
              yield FireworksStreamResponse.new(chunk)
            end

            req.options.on_data = to_json_stream(user_proc: user_proc)
          end

          # For streaming, errors are handled in to_json_stream, no need for handle_response
          nil
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

        def handle_response(response, response_class = FireworksResponse)
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

        # Response object for Fireworks chat API responses.
        #
        # Wraps the raw response and provides a consistent interface for accessing
        # message content and metadata.
        class FireworksResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| FireworksChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single choice in a Fireworks response.
        #
        # Contains the message and finish reason for the choice.
        class FireworksChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = FireworksMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in a Fireworks conversation.
        #
        # Messages have a role (user, assistant) and text content.
        class FireworksMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Response object for streaming Fireworks chat chunks.
        #
        # Wraps individual chunks from the Server-Sent Events stream.
        class FireworksStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = FireworksStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Response object for Fireworks embedding API responses.
        #
        # Wraps embedding data and provides array access to the vector representation.
        class FireworksEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Represents a single choice in a streaming Fireworks response chunk.
        #
        # Contains the delta (incremental content) and finish reason for the choice.
        class FireworksStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = FireworksStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the role and text content of the delta.
        class FireworksStreamDelta
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
