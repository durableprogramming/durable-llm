# frozen_string_literal: true

# This file implements the Hugging Face provider for accessing Hugging Face's inference API models.

require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'
require 'event_stream_parser'

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
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
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

        def stream(options)
          model = options.delete(:model) || 'gpt2'
          options[:stream] = true

          @conn.post("models/#{model}") do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Accept'] = 'text/event-stream'
            req.body = options
            req.options.on_data = to_json_stream(user_proc: proc { |chunk|
              yield HuggingfaceStreamResponse.new(chunk)
            })
          end
        end

        def self.models
          %w[gpt2 bert-base-uncased distilbert-base-uncased] # could use expansion
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
