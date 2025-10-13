# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm'

class TestProviderHuggingface < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Huggingface.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  # def test_default_api_key
  #   ENV['HUGGINGFACE_API_KEY'] = 'env_api_key'
  #   provider = Durable::Llm::Providers::Huggingface.new
  #   assert_equal 'env_api_key', provider.default_api_key
  #   ENV.delete('HUGGINGFACE_API_KEY')
  # end

  def test_completion
    stub_request(:post, 'https://api-inference.huggingface.co/models/gpt2')
      .to_return(status: 200, body: {
        generated_text: 'Test response'
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(inputs: 'Hello world')

    assert_instance_of Durable::Llm::Providers::Huggingface::HuggingfaceResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://api-inference.huggingface.co/models/bert-base-uncased')
      .to_return(status: 200, body: [[0.1, 0.2, 0.3]], headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'bert-base-uncased', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::Huggingface::HuggingfaceEmbeddingResponse, response
    assert_equal [[0.1, 0.2, 0.3]], response.to_a
  end

  def test_models
    models = @provider.models

    assert_includes models, 'gpt2'
    assert_includes models, 'bert-base-uncased'
  end

  def test_stream
    chunks = [
      { token: { text: 'Hello' } },
      { token: { text: ' world' } },
      { token: { text: '!' } }
    ]

    stub_request(:post, 'https://api-inference.huggingface.co/models/gpt2')
      .to_return(status: 200, body: chunks.map { |chunk|
                   "data: #{chunk.to_json}\n\n"
                 }.join + "data: [DONE]\n\n", headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(inputs: 'Hello') do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    stub_request(:post, 'https://api-inference.huggingface.co/models/gpt2')
      .to_return(status: 401, body: { error: 'Unauthorized' }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(inputs: 'Hello')
    end
  end
end
