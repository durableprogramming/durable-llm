
require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class Anthropic < Durable::Llm::Providers::Base
        BASE_URL = 'https://api.anthropic.com'

        def default_api_key
          Durable::Llm.configuration.anthropic&.api_key || ENV['ANTHROPIC_API_KEY']
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
          options['max_tokens'] ||=1024
          response = @conn.post('/v1/messages') do |req|
            req.headers['x-api-key'] = @api_key
            req.headers['anthropic-version'] = '2023-06-01'
            req.body = options
          end

          handle_response(response)
        end

        def models
          self.class.models
        end
        def self.models
          ['claude-3-5-sonnet-20240620', 'claude-3-opus-20240229', 'claude-3-haiku-20240307']
        end

        def self.stream?
          true
        end
        def stream(options, &block)
          options[:stream] = true
          response = @conn.post('/v1/messages') do |req|
            req.headers['x-api-key'] = @api_key
            req.headers['anthropic-version'] = '2023-06-01'
            req.headers['Accept'] = 'text/event-stream'
            req.body = options
            req.options.on_data = Proc.new do |chunk, size, total|
              next if chunk.strip.empty?
              yield AnthropicStreamResponse.new(chunk) if chunk.start_with?('data: ')
            end
          end

          handle_response(response)
        end

        private

        def handle_response(response)
              case response.status
              when 200..299
                AnthropicResponse.new(response.body)
              when 401
                raise Durable::Llm::AuthenticationError, response.body.dig('error', 'message')
              when 429
                raise Durable::Llm::RateLimitError, response.body.dig('error', 'message')
              when 400..499
                raise Durable::Llm::InvalidRequestError, response.body.dig('error', 'message')
              when 500..599
                raise Durable::Llm::ServerError, response.body.dig('error', 'message')
              else
                raise Durable::Llm::APIError, "Unexpected response code: #{response.status}"
              end
        end

        class AnthropicResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            [@raw_response['content']].map { |content| AnthropicChoice.new(content) }
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        class AnthropicChoice
          attr_reader :message

          def initialize(content)
            @message = AnthropicMessage.new(content)
          end

          def to_s
            @message.to_s
          end
        end

        class AnthropicMessage
          attr_reader :role, :content

          def initialize(content)
            @role = [content].flatten.map { |_| _['type']}.join(' ')
            @content = [content].flatten.map { |_| _['text']}.join(' ')
          end

          def to_s
            @content
          end
        end

        class AnthropicStreamResponse
          attr_reader :choices

          def initialize(fragment)
            parsed = JSON.parse(fragment.split("data: ").last)
            @choices = [AnthropicStreamChoice.new(parsed['delta'])]
          end

          def to_s
            @choices.map(&:to_s).join(' ')
          end
        end

        class AnthropicStreamChoice
          attr_reader :delta

          def initialize(delta)
            @delta = AnthropicStreamDelta.new(delta)
          end

          def to_s
            @delta.to_s
          end
        end

        class AnthropicStreamDelta
          attr_reader :type, :text

          def initialize(delta)
            @type = delta['type']
            @text = delta['text']
          end

          def to_s
            @text || ''
          end
        end
      end
    end
  end
end
