# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm'
require 'durable/llm/providers'

Durable::Llm.configuration.clear

class TestProviderDeepSeek < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::DeepSeek.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['DEEPSEEK_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::DeepSeek.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('DEEPSEEK_API_KEY')
  end

  def test_completion
    body = { choices: [{ message: { role: 'assistant', content: 'Test response' } }] }.to_json
    stub_request(:post, 'https://api.deepseek.com/chat/completions')
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(model: 'deepseek-chat', messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::DeepSeek::DeepSeekResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://api.deepseek.com/embeddings')
      .to_return(status: 200, body: {
        data: [
          { embedding: [0.1, 0.2, 0.3] }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'text-embedding', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::DeepSeek::DeepSeekEmbeddingResponse, response
    assert_equal [0.1, 0.2, 0.3], response.embedding.map(&:to_f)
  end

  def test_models
    stub_request(:get, 'https://api.deepseek.com/models')
      .to_return(status: 200, body: {
        data: [
          { id: 'deepseek-chat' },
          { id: 'deepseek-coder' }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    models = @provider.models

    assert_includes models, 'deepseek-chat'
    assert_includes models, 'deepseek-coder'
  end

  def test_stream
    chunks = [{ choices: [{ delta: { content: 'Hello' } }] }, { choices: [{ delta: { content: ' world' } }] },
              { choices: [{ delta: { content: '!' } }] }]
    body = "#{chunks.map { |chunk| "data: #{chunk.to_json}\n\n" }.join}data: [DONE]\n\n"
    stub_request(:post, 'https://api.deepseek.com/chat/completions')
      .to_return(status: 200, body: body, headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(model: 'deepseek-chat', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    body = { error: { message: 'Unauthorized' } }.to_json
    stub_request(:post, 'https://api.deepseek.com/chat/completions')
      .to_return(status: 401, body: body, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'deepseek-chat', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_rate_limit_error
    body = { error: { message: 'Rate limit exceeded' } }.to_json
    stub_request(:post, 'https://api.deepseek.com/chat/completions')
      .to_return(status: 429, body: body, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::RateLimitError do
      @provider.completion(model: 'deepseek-chat', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
