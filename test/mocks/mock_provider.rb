# frozen_string_literal: true

require 'durable/llm/providers/base'

module Durable
  module Llm
    module Providers
      class MockProvider < Durable::Llm::Providers::Base
        def default_api_key
          'mock_api_key'
        end

        def completion(_options)
          MockResponse.new({ 'choices' => [{ 'message' => { 'content' => 'Mock completion response' } }] })
        end

        def models
          %w[mock-model-1 mock-model-2]
        end

        def self.models
          %w[mock-model-1 mock-model-2]
        end

        def self.stream?
          true
        end

        def stream(_options)
          yield MockStreamResponse.new('Mock stream response')
        end

        def embedding(model:, input:, **_options)
          MockEmbeddingResponse.new({ 'data' => [{ 'embedding' => [0.1, 0.2, 0.3] }] })
        end

        private

        def handle_response(response)
          case response.status
          when 200..299
            MockResponse.new(response.body)
          when 401
            raise Durable::Llm::AuthenticationError, 'Mock authentication error'
          when 429
            raise Durable::Llm::RateLimitError, 'Mock rate limit error'
          when 400..499
            raise Durable::Llm::InvalidRequestError, 'Mock invalid request error'
          when 500..599
            raise Durable::Llm::ServerError, 'Mock server error'
          else
            raise Durable::Llm::APIError, "Mock unexpected response code: #{response.status}"
          end
        end

        class MockResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| MockChoice.new(choice) }
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        class MockChoice
          attr_reader :message

          def initialize(choice)
            @message = MockMessage.new(choice['message'])
          end

          def to_s
            @message.to_s
          end
        end

        class MockMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        class MockStreamResponse
          attr_reader :choices

          def initialize(content)
            @choices = [MockStreamChoice.new(content)]
          end

          def to_s
            @choices.map(&:to_s).join(' ')
          end
        end

        class MockStreamChoice
          attr_reader :delta

          def initialize(content)
            @delta = MockStreamDelta.new(content)
          end

          def to_s
            @delta.to_s
          end
        end

        class MockStreamDelta
          attr_reader :content

          def initialize(content)
            @content = content
          end

          def to_s
            @content
          end
        end

        class MockEmbeddingResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def embeddings
            @raw_response['data'].map { |embedding| embedding['embedding'] }
          end
        end
      end
    end
  end
end
