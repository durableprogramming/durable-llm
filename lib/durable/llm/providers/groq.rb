require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class Groq < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.groq.com/openai/v1'

        def default_api_key
          Durable::Llm.configuration.groq&.api_key || ENV['GROQ_API_KEY']
        end

        attr_accessor :api_key

        def self.conn
          Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        def conn
          self.class.conn
        end

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
        end

        def completion(options)
          response = conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.body = { model: model, input: input, **options }
          end

          handle_response(response)
        end

        def models
          response = conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
          end

          resp = handle_response(response).to_h

          resp['data'].map { |model| model['id'] }
        end

        def self.stream?
          false
        end

        private

        def handle_response(response)
          case response.status
          when 200..299
            GroqResponse.new(response.body)
          when 401
            raise Durable::Llm::AuthenticationError, response.body['error']['message']
          when 429
            raise Durable::Llm::RateLimitError, response.body['error']['message']
          when 400..499
            raise Durable::Llm::InvalidRequestError, response.body['error']['message']
          when 500..599
            raise Durable::Llm::ServerError, response.body['error']['message']
          else
            raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
          end
        end

        class GroqResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| GroqChoice.new(choice) }
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end

          def to_h
            @raw_response.dup
          end
        end

        class GroqChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = GroqMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        class GroqMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        class GroqStreamResponse
          attr_reader :choices

          def initialize(fragment)
            json_frag = fragment.split('data: ').last.strip
            puts json_frag
            parsed = JSON.parse(json_frag)
            @choices = parsed['choices'].map { |choice| GroqStreamChoice.new(choice) }
          end

          def to_s
            @choices.map(&:to_s).join(' ')
          end
        end

        class GroqStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @delta = GroqStreamDelta.new(choice['delta'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        class GroqStreamDelta
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
