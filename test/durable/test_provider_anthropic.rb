require 'minitest/autorun'
require 'webmock/minitest'
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
      'role': 'assistant',
      'content' => [
        {
          'type' => 'text',
          'text' => 'Test response'
        }
      ]
    }
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: response_data.to_json, headers: { 'Content-Type' => 'application/json' })
    
    response = @provider.completion(model: 'claude-2.1', messages: [{ role: 'user', content: 'Hello' }])
    
    assert_instance_of Durable::Llm::Providers::Anthropic::AnthropicResponse, response
    assert_equal 'Test response', response.choices.first.to_s
    assert_requested :post, "https://api.anthropic.com/v1/messages"
  end

  def test_models
    assert @provider.models.kind_of?(Array)
    assert @provider.models.length > 0
    assert @provider.models.all? { |_| _.kind_of?(String)}
  end

  def test_handle_response_error
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 401, body: { 'error' => { 'message' => 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'claude-2.1', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
