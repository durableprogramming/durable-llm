require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class OpenAI < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.openai.com/v1'

        def default_api_key
          Durable::Llm.configuration.openai&.api_key || ENV['OPENAI_API_KEY']
        end

        attr_accessor :api_key, :organization

        def initialize(api_key: nil, organization: nil)
          @api_key = api_key || default_api_key
          @organization = organization || ENV['OPENAI_ORGANIZATION']
          @conn = Faraday.new(url: BASE_URL) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        def completion(options)
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          response = @conn.post('embeddings') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
            req.body = { model: model, input: input, **options }
          end

          handle_response(response, OpenAIEmbeddingResponse)
        end

        def models
          response = @conn.get('models') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
          end

          handle_response(response).data.map { |model| model['id'] }
        end

        def self.models
          self.new.models 
        end

        def self.stream?
          true
        end

        def stream(options, &block)
          options[:stream] = true
          response = @conn.post('chat/completions') do |req|
            req.headers['Authorization'] = "Bearer #{@api_key}"
            req.headers['OpenAI-Organization'] = @organization if @organization
            req.headers['Accept'] = 'text/event-stream'
            req.body = options
            req.options.on_data = Proc.new do |chunk, size, total|
              next if chunk.strip.empty?

              yield OpenAIStreamResponse.new(chunk)
            end
          end

          handle_response(response)
        end

        private

        def handle_response(response, responseClass=OpenAIResponse)
          case response.status
          when 200..299
            responseClass.new(response.body)
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
          body = JSON.parse(response.body) rescue nil
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

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

        class OpenAIStreamResponse
          attr_reader :choices

          def initialize(fragment)
            parsed = fragment.split("\n").map { |_|  JSON.parse(_) }

            @choices = parsed.map { |_| OpenAIStreamChoice.new(_['choices'])}
          end

          def to_s
            @choices.map(&:to_s).join('')
          end
        end

        class OpenAIEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

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
