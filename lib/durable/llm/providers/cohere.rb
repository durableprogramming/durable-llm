# This file implements the Cohere provider for accessing Cohere's language models through their API, providing completion capabilities with authentication handling, error management, and response normalization. It establishes HTTP connections to Cohere's v2 API endpoint, processes chat completions, handles various API error responses, and includes custom response classes to format Cohere's API responses into a consistent interface compatible with the unified provider system.

require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class Cohere < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.cohere.ai/v2'

        def default_api_key
          Durable::Llm.configuration.cohere&.api_key || ENV['COHERE_API_KEY']
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        def completion(options)
          response = @conn.post('chat') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['Content-Type'] = 'application/json'
            req.body = options
          end

          handle_response(response)
        end

        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
          end

          data = handle_response(response).raw_response
          data['models']&.map { |model| model['name'] }
        end

        def self.stream?
          false
        end

        private

        def handle_response(response)
          case response.status
          when 200..299
            CohereResponse.new(response.body)
          when 401
            raise Durable::Llm::AuthenticationError, response.body['message']
          when 429
            raise Durable::Llm::RateLimitError, response.body['message']
          when 400..499
            raise Durable::Llm::InvalidRequestError, response.body['message']
          when 500..599
            raise Durable::Llm::ServerError, response.body['message']
          else
            raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
          end
        end

        class CohereResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [@raw_response.dig('message', 'content')].flatten.map { |generation| CohereChoice.new(generation) }
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        class CohereChoice
          attr_reader :text

          def initialize(generation)
            @text = generation['text']
          end

          def to_s
            @text
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.