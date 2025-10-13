# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm/providers/together'

class TestProviderTogether < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Together.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['TOGETHER_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::Together.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('TOGETHER_API_KEY')
  end

  def test_completion
    stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
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

    response = @provider.completion(model: 'meta-llama/Llama-2-7b-chat-hf',
                                    messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::Together::TogetherResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://api.together.xyz/v1/embeddings')
      .to_return(status: 200, body: {
        data: [
          { embedding: [0.1, 0.2, 0.3] }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'togethercomputer/m2-bert-80M-8k-retrieval', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::Together::TogetherEmbeddingResponse, response
    assert_equal [0.1, 0.2, 0.3], response.to_a
  end

  def test_models
    stub_request(:get, 'https://api.together.xyz/v1/models')
      .to_return(status: 200, body: {
        data: [
          { id: 'meta-llama/Llama-2-7b-chat-hf' },
          { id: 'togethercomputer/m2-bert-80M-8k-retrieval' }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    models = @provider.models

    assert_includes models, 'meta-llama/Llama-2-7b-chat-hf'
    assert_includes models, 'togethercomputer/m2-bert-80M-8k-retrieval'
  end

  def test_stream
    chunks = [
      { choices: [{ delta: { content: 'Hello' } }] },
      { choices: [{ delta: { content: ' world' } }] },
      { choices: [{ delta: { content: '!' } }] }
    ]

    stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
      .to_return(status: 200, body: chunks.map { |chunk|
                   "data: #{chunk.to_json}\n\n"
                 }.join + "data: [DONE]\n\n", headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(model: 'meta-llama/Llama-2-7b-chat-hf', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    stub_request(:post, 'https://api.together.xyz/v1/chat/completions')
      .to_return(status: 401, body: { error: { message: 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'meta-llama/Llama-2-7b-chat-hf', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
