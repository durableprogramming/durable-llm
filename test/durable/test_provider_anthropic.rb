# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm'
require 'durable/llm/providers/anthropic'

class TestProviderAnthropic < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Anthropic.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['ANTHROPIC_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::Anthropic.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('ANTHROPIC_API_KEY')
  end

  def test_completion
    response_data = {
      'id' => 'msg_123',
      'type' => 'message',
      'role' => 'assistant',
      'content' => [
        {
          'type' => 'text',
          'text' => 'Test response'
        }
      ],
      'model' => 'claude-3-5-sonnet-20240620',
      'stop_reason' => 'end_turn',
      'usage' => {
        'input_tokens' => 10,
        'output_tokens' => 25
      }
    }
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: response_data.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(model: 'claude-3-5-sonnet-20240620',
                                    messages: [{ role: 'user',
                                                 content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::Anthropic::AnthropicResponse, response
    assert_equal 'Test response', response.choices.first.to_s
    assert_equal 'end_turn', response.choices.first.stop_reason
    assert_equal({ 'input_tokens' => 10, 'output_tokens' => 25 }, response.usage)
    assert_requested :post, 'https://api.anthropic.com/v1/messages'
  end

  def test_completion_with_system_message
    response_data = {
      'id' => 'msg_123',
      'type' => 'message',
      'role' => 'assistant',
      'content' => [
        {
          'type' => 'text',
          'text' => 'Hello! How can I help you?'
        }
      ]
    }
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: response_data.to_json, headers: { 'Content-Type' => 'application/json' })

    messages = [
      { role: 'system', content: 'You are a helpful assistant.' },
      { role: 'user', content: 'Hello' }
    ]
    response = @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: messages)

    assert_equal 'Hello! How can I help you?', response.choices.first.to_s
    assert_requested(:post, 'https://api.anthropic.com/v1/messages') do |req|
      body = JSON.parse(req.body)
      assert_equal 'You are a helpful assistant.', body['system']
      assert_equal [{ 'role' => 'user', 'content' => 'Hello' }], body['messages']
    end
  end

  def test_completion_with_max_tokens
    response_data = {
      'role' => 'assistant',
      'content' => [{ 'type' => 'text', 'text' => 'Short response' }]
    }
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: response_data.to_json, headers: { 'Content-Type' => 'application/json' })

    @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }],
                         max_tokens: 50)

    assert_requested(:post, 'https://api.anthropic.com/v1/messages') do |req|
      body = JSON.parse(req.body)
      assert_equal 50, body['max_tokens']
    end
  end

  def test_completion_default_max_tokens
    response_data = {
      'role' => 'assistant',
      'content' => [{ 'type' => 'text', 'text' => 'Response' }]
    }
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: response_data.to_json, headers: { 'Content-Type' => 'application/json' })

    @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])

    assert_requested(:post, 'https://api.anthropic.com/v1/messages') do |req|
      body = JSON.parse(req.body)
      assert_equal 1024, body['max_tokens']
    end
  end

  def test_models
    assert @provider.models.is_a?(Array)
    assert @provider.models.length.positive?
    assert(@provider.models.all? { |_| _.is_a?(String) })
  end

  def test_handle_response_error_401
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 401, body: { 'error' => { 'message' => 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_handle_response_error_429
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 429, body: { 'error' => { 'message' => 'Rate limit exceeded' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::RateLimitError do
      @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_handle_response_error_400
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 400, body: { 'error' => { 'message' => 'Invalid request' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::InvalidRequestError do
      @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_handle_response_error_500
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 500, body: { 'error' => { 'message' => 'Internal server error' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::ServerError do
      @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_handle_response_error_unexpected
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 418, body: 'I\'m a teapot', headers: { 'Content-Type' => 'text/plain' })

    assert_raises Durable::Llm::InvalidRequestError do
      @provider.completion(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }])
    end
  end

  def test_embedding_not_implemented
    assert_raises NotImplementedError do
      @provider.embedding(model: 'claude-2.1', input: 'test')
    end
  end

  def test_stream
    stream_data = "data: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \"Hello\"}}\n\ndata: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \" world\"}}\n\n"
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: stream_data, headers: { 'Content-Type' => 'text/event-stream' })

    chunks = []
    @provider.stream(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      chunks << chunk.to_s
    end

    assert_equal ['Hello', ' world'], chunks
  end

  def test_stream_with_system_message
    stream_data = "data: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \"Hi\"}}\n\n"
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(status: 200, body: stream_data, headers: { 'Content-Type' => 'text/event-stream' })

    messages = [
      { role: 'system', content: 'You are a helpful assistant.' },
      { role: 'user', content: 'Hello' }
    ]
    chunks = []
    @provider.stream(model: 'claude-3-5-sonnet-20240620', messages: messages) do |chunk|
      chunks << chunk.to_s
    end

    assert_equal ['Hi'], chunks
    assert_requested(:post, 'https://api.anthropic.com/v1/messages') do |req|
      body = JSON.parse(req.body)
      assert_equal 'You are a helpful assistant.', body['system']
      assert_equal [{ 'role' => 'user', 'content' => 'Hello' }], body['messages']
    end
  end

  def test_stream_class_method
    assert_equal true, Durable::Llm::Providers::Anthropic.stream?
  end
end
