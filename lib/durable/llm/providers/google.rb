# frozen_string_literal: true

# This file implements the Google provider for accessing Google's Gemini language models through their API, providing completion capabilities with authentication handling, error management, and response normalization. It establishes HTTP connections to Google's Generative Language API endpoint, processes generateContent requests with text content, handles various API error responses, and includes comprehensive response classes to format Google's API responses into a consistent interface.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Google Generative AI provider for accessing Gemini language models.
      #
      # Provides completion, embedding, and streaming capabilities with proper
      # error handling and response normalization for Google's Generative Language API.
      class Google < Durable::Llm::Providers::Base
        BASE_URL = 'https://generativelanguage.googleapis.com'

        def default_api_key
          begin
            Durable::Llm.configuration.google&.api_key
          rescue NoMethodError
            nil
          end || ENV['GOOGLE_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
        end

        def completion(options)
          model = options[:model]
          url = "/v1beta/models/#{model}:generateContent?key=#{@api_key}"

          # Transform options to Google's format
          request_body = transform_options(options)

          response = @conn.post(url) do |req|
            req.body = request_body
          end

          handle_response(response)
        end

        def embedding(model:, input:, **_options)
          url = "/v1beta/models/#{model}:embedContent?key=#{@api_key}"

          request_body = {
            content: {
              parts: [{ text: input }]
            }
          }

          response = @conn.post(url) do |req|
            req.body = request_body
          end

          handle_response(response, GoogleEmbeddingResponse)
        end

        def models
          # Google doesn't provide a public models API, so return hardcoded list
          [
            'gemini-1.5-flash',
            'gemini-1.5-flash-001',
            'gemini-1.5-flash-002',
            'gemini-1.5-flash-8b',
            'gemini-1.5-flash-8b-001',
            'gemini-1.5-flash-8b-latest',
            'gemini-1.5-flash-latest',
            'gemini-1.5-pro',
            'gemini-1.5-pro-001',
            'gemini-1.5-pro-002',
            'gemini-1.5-pro-latest',
            'gemini-2.0-flash',
            'gemini-2.0-flash-001',
            'gemini-2.0-flash-exp',
            'gemini-2.0-flash-lite',
            'gemini-2.0-flash-lite-001',
            'gemini-2.0-flash-live-001',
            'gemini-2.0-flash-preview-image-generation',
            'gemini-2.5-flash',
            'gemini-2.5-flash-exp-native-audio-thinking-dialog',
            'gemini-2.5-flash-lite',
            'gemini-2.5-flash-lite-06-17',
            'gemini-2.5-flash-preview-05-20',
            'gemini-2.5-flash-preview-native-audio-dialog',
            'gemini-2.5-flash-preview-tts',
            'gemini-2.5-pro',
            'gemini-2.5-pro-preview-tts',
            'gemini-live-2.5-flash-preview',
            'text-embedding-004',
            'text-multilingual-embedding-002'
          ]
        end

        def self.stream?
          true
        end
        def stream(options, &block)
          model = options[:model]
          url = "/v1beta/models/#{model}:streamGenerateContent?key=#{@api_key}&alt=sse"

          request_body = transform_options(options)

          response = @conn.post_stream(url) do |stream|
            stream.on_chunk { |chunk| block.call(GoogleStreamResponse.new(chunk)) }
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = request_body
          end

          handle_response(response)
        end

        private

        def transform_options(options)
          messages = options[:messages] || []
          system_messages = messages.select { |m| m[:role] == 'system' }
          conversation_messages = messages.reject { |m| m[:role] == 'system' }

          body = {
            contents: conversation_messages.map do |msg|
              {
                role: msg[:role] == 'assistant' ? 'model' : 'user',
                parts: [{ text: msg[:content] }]
              }
            end
          }

          if system_messages.any?
            body[:systemInstruction] = {
              parts: [{ text: system_messages.map { |m| m[:content] }.join("\n") }]
            }
          end

          generation_config = {}
          generation_config[:temperature] = options[:temperature] if options[:temperature]
          generation_config[:maxOutputTokens] = options[:max_tokens] if options[:max_tokens]
          generation_config[:topP] = options[:top_p] if options[:top_p]
          generation_config[:topK] = options[:top_k] if options[:top_k]

          body[:generationConfig] = generation_config unless generation_config.empty?

          body
        end

        def handle_response(response, response_class = GoogleResponse)
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

        # Response object for Google Generative AI API responses.
        #
        # Wraps the raw response and provides a consistent interface for accessing
        # candidate content and metadata.
        class GoogleResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [GoogleChoice.new(@raw_response['candidates']&.first)]
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Represents a single candidate choice in a Google response.
        #
        # Contains the message content from the candidate.
        class GoogleChoice
          attr_reader :message

          def initialize(candidate)
            @message = GoogleMessage.new(candidate&.dig('content', 'parts')&.first)
          end

          def to_s
            @message.to_s
          end
        end

        # Represents a message in a Google conversation.
        #
        # Messages contain text content extracted from parts.
        class GoogleMessage
          attr_reader :content

          def initialize(part)
            @content = part&.dig('text') || ''
          end

          def to_s
            @content
          end
        end

        # Response object for streaming Google Generative AI chunks.
        #
        # Wraps individual chunks from the streaming response.
        class GoogleStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = [GoogleStreamChoice.new(parsed)]
          end

          def to_s
            @choices.map(&:to_s).join
          end
        end

        # Represents a single choice in a streaming Google response chunk.
        #
        # Contains the delta (incremental content) for the choice.
        class GoogleStreamChoice
          attr_reader :delta

          def initialize(parsed)
            @delta = GoogleStreamDelta.new(parsed.dig('candidates', 0, 'content', 'parts', 0))
          end

          def to_s
            @delta.to_s
          end
        end

        # Represents the incremental content delta in a streaming response.
        #
        # Contains the text content of the delta.
        class GoogleStreamDelta
          attr_reader :content

          def initialize(part)
            @content = part&.dig('text') || ''
          end

          def to_s
            @content
          end
        end

        # Response object for Google embedding API responses.
        #
        # Wraps embedding data and provides array access to the vector representation.
        class GoogleEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('embedding', 'values')
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
