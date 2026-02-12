# frozen_string_literal: true

# This file implements the Hugging Face provider for accessing Hugging Face's inference API models.

require 'durable/llm/http_client'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      # Hugging Face provider for accessing Hugging Face's inference API models.
      #
      # Provides completion, embedding, and streaming capabilities with authentication
      # handling, error management, and response normalization.
      class Huggingface < Durable::Llm::Providers::Base
        BASE_URL = 'https://api-inference.huggingface.co'

        def default_api_key
          Durable::Llm.configuration.huggingface&.api_key || ENV['HUGGINGFACE_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
          @conn = Durable::Llm::HttpClient.new(url: BASE_URL)
          super()
        end

        def completion(options)
          model = options.delete(:model) || 'gpt2'
          response = @conn.post("models/#{model}") do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = @conn.post("models/#{model}") do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { inputs: input, **options }
          end

          handle_response(response, HuggingfaceEmbeddingResponse)
        end

        def models
          self.class.models
        end

        def self.stream?
          true
        end
        def stream(options, &block)
          model = options.delete(:model) || 'gpt2'
          options[:stream] = true

          response = @conn.post_stream("models/#{model}") do |stream|
            stream.on_chunk { |chunk| block.call(HuggingfaceStreamResponse.new(chunk)) }
            stream.headers['Authorization'] = "Bearer #{@api_key}"
            stream.headers['Accept'] = 'text/event-stream'
            stream.body = options
          end

          handle_response(response)
        end

        def self.models
          %w[gpt2 bert-base-uncased distilbert-base-uncased] # could use expansion
        end

        private

        def handle_response(response, response_class = HuggingfaceResponse)
          return response_class.new(response.body) if (200..299).cover?(response.status)

          error_class = error_class_for_status(response.status)
          raise error_class, response.body['error'] || "HTTP #{response.status}"
        end

        def error_class_for_status(status)
          case status
          when 401 then Durable::Llm::AuthenticationError
          when 429 then Durable::Llm::RateLimitError
          when 400..499 then Durable::Llm::InvalidRequestError
          when 500..599 then Durable::Llm::ServerError
          else Durable::Llm::APIError
          end
        end

        # Response wrapper for Hugging Face completion API responses.
        class HuggingfaceResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [HuggingfaceChoice.new(@raw_response)]
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Individual choice from Hugging Face completion response.
        class HuggingfaceChoice
          attr_reader :text

          def initialize(choice)
            @text = choice['generated_text']
          end

          def to_s
            @text
          end
        end

        # Response wrapper for Hugging Face embedding API responses.
        class HuggingfaceEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data
          end

          def to_a
            @embedding
          end
        end

        # Response wrapper for Hugging Face streaming API responses.
        class HuggingfaceStreamResponse
          attr_reader :token

          def initialize(parsed)
            @token = HuggingfaceStreamToken.new(parsed)
          end

          def to_s
            @token.to_s
          end
        end

        # Individual token from Hugging Face streaming response.
        class HuggingfaceStreamToken
          attr_reader :text

          def initialize(token)
            @text = token['token']['text']
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
