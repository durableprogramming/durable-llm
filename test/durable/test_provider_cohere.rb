# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm/providers/cohere'

class TestProviderCohere < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Cohere.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['COHERE_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::Cohere.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('COHERE_API_KEY')
  end

  def test_completion
    stub_request(:post, 'https://api.cohere.ai/v2/chat')
      .to_return(status: 200, body: {
        message: {
          content: { text: 'Test response' }
        }
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(model: 'command', messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::Cohere::CohereResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_models
    stub_request(:get, 'https://api.cohere.ai/v2/models')
      .to_return(status: 200, body: {
        models: [
          { name: 'command' },
          { name: 'command-light' }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    models = @provider.models

    assert_includes models, 'command'
    assert_includes models, 'command-light'
  end

  def test_handle_response_error
    stub_request(:post, 'https://api.cohere.ai/v2/chat')
      .to_return(status: 401, body: { message: 'Unauthorized' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'command', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_stream
    assert_equal false, Durable::Llm::Providers::Cohere.stream?
  end
end
