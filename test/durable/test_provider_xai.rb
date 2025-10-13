# frozen_string_literal: true

require 'test_helper'
require 'webmock/minitest'
require 'durable/llm/providers/xai'

class TestProviderXai < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Xai.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['XAI_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::Xai.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('XAI_API_KEY')
  end

  def test_completion
    stub_request(:post, 'https://api.x.ai/v1/chat/completions')
      .to_return(status: 200, body: {
        choices: [
          {
            message: {
              role: 'assistant',
              content: 'Test response'
            }
          }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(model: 'grok-1', messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::Xai::XaiResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://api.x.ai/v1/embeddings')
      .to_return(status: 200, body: {
        data: [
          { embedding: [0.1, 0.2, 0.3] }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'text-embedding-ada-002', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::Xai::XaiEmbeddingResponse, response
    assert_equal [0.1, 0.2, 0.3], response.embedding.map(&:to_f)
  end

  def test_models
    stub_request(:get, 'https://api.x.ai/v1/models')
      .to_return(status: 200, body: {
        data: [
          { id: 'grok-1' },
          { id: 'grok-2' }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    models = @provider.models

    assert_includes models, 'grok-1'
    assert_includes models, 'grok-2'
  end

  def test_stream
    chunks = [
      { choices: [{ delta: { content: 'Hello' } }] },
      { choices: [{ delta: { content: ' world' } }] },
      { choices: [{ delta: { content: '!' } }] }
    ]

    stub_request(:post, 'https://api.x.ai/v1/chat/completions')
      .to_return(status: 200, body: chunks.map { |chunk|
                   "data: #{chunk.to_json}\n\n"
                 }.join + "data: [DONE]\n\n", headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(model: 'grok-1', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    stub_request(:post, 'https://api.x.ai/v1/chat/completions')
      .to_return(status: 401, body: { error: { message: 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'grok-1', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
