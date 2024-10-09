require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class Huggingface < Durable::Llm::Providers::Base
        BASE_URL = 'https://api-inference.huggingface.co/models'

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
        end

        def completion(options)
          model = options.delete(:model) || 'gpt2'
          response = @conn.post("/#{model}") do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        def models
          self.class.models
        end
        def self.models
          ['gpt2', 'bert-base-uncased', 'distilbert-base-uncased'] # could use expansion
        end

        private

        def handle_response(response)
          case response.status
          when 200..299
            HuggingfaceResponse.new(response.body)
          when 401
            raise Durable::Llm::AuthenticationError, response.body['error']
          when 429
            raise Durable::Llm::RateLimitError, response.body['error']
          when 400..499
            raise Durable::Llm::InvalidRequestError, response.body['error']
          when 500..599
            raise Durable::Llm::ServerError, response.body['error']
          else
            raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
          end
        end

        class HuggingfaceResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [@raw_response.first].map { |choice| HuggingfaceChoice.new(choice) }
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        class HuggingfaceChoice
          attr_reader :text

          def initialize(choice)
            @text = choice['generated_text']
          end

          def to_s
            @text
          end
        end
      end
    end
  end
end
