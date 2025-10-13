# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm/providers/azure_openai'

class TestProviderAzureOpenAI < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::AzureOpenai.new(
      api_key: 'test_api_key',
      resource_name: 'test-resource',
      api_version: '2024-02-01'
    )
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['AZURE_OPENAI_API_KEY'] = 'env_api_key'
    ENV['AZURE_OPENAI_RESOURCE_NAME'] = 'env_resource'
    provider = Durable::Llm::Providers::AzureOpenai.new
    assert_equal 'env_api_key', provider.api_key
    assert_equal 'env_resource', provider.resource_name
    ENV.delete('AZURE_OPENAI_API_KEY')
    ENV.delete('AZURE_OPENAI_RESOURCE_NAME')
  end

  def test_completion
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
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

    response = @provider.completion(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::AzureOpenai::AzureOpenaiResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2024-02-01')
      .to_return(status: 200, body: {
        data: [
          { embedding: [0.1, 0.2, 0.3] }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'text-embedding-ada-002', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::AzureOpenai::AzureOpenaiEmbeddingResponse, response
    assert_equal [0.1, 0.2, 0.3], response.to_a
    assert_equal [0.1, 0.2, 0.3], response.embedding
  end

  def test_models
    models = @provider.models

    assert_includes models, 'gpt-4o'
    assert_includes models, 'gpt-3.5-turbo'
    assert_includes models, 'text-embedding-ada-002'
  end

  def test_stream
    chunks = [
      { choices: [{ delta: { content: 'Hello' } }] },
      { choices: [{ delta: { content: ' world' } }] },
      { choices: [{ delta: { content: '!' } }] }
    ]

    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
      .to_return(status: 200, body: chunks.map { |chunk|
                   "data: #{chunk.to_json}\n\n"
                 }.join + "data: [DONE]\n\n", headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
      .to_return(status: 401, body: { error: { message: 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_rate_limit_error
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
      .to_return(status: 429, body: { error: { message: 'Rate limit exceeded' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::RateLimitError do
      @provider.completion(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_invalid_request_error
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
      .to_return(status: 400, body: { error: { message: 'Bad Request' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::InvalidRequestError do
      @provider.completion(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_server_error
    stub_request(:post, 'https://test-resource.openai.azure.com/openai/deployments/gpt-3.5-turbo/chat/completions?api-version=2024-02-01')
      .to_return(status: 500, body: { error: { message: 'Internal Server Error' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::ServerError do
      @provider.completion(model: 'gpt-3.5-turbo', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
