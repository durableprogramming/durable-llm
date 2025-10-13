# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'durable/llm/providers/google'

class TestProviderGoogle < Minitest::Test
  def setup
    WebMock.disable_net_connect!
    @provider = Durable::Llm::Providers::Google.new(api_key: 'test_api_key')
  end

  def teardown
    WebMock.reset!
  end

  def test_default_api_key
    ENV['GOOGLE_API_KEY'] = 'env_api_key'
    provider = Durable::Llm::Providers::Google.new
    assert_equal 'env_api_key', provider.default_api_key
    ENV.delete('GOOGLE_API_KEY')
  end

  def test_completion
    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=test_api_key')
      .to_return(status: 200, body: {
        candidates: [
          {
            content: {
              parts: [
                { text: 'Test response' }
              ]
            }
          }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(model: 'gemini-1.5-flash', messages: [{ role: 'user', content: 'Hello' }])

    assert_instance_of Durable::Llm::Providers::Google::GoogleResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_completion_with_system_message
    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=test_api_key')
      .to_return(status: 200, body: {
        candidates: [
          {
            content: {
              parts: [
                { text: 'Test response' }
              ]
            }
          }
        ]
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.completion(
      model: 'gemini-1.5-flash',
      messages: [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Hello' }
      ]
    )

    assert_instance_of Durable::Llm::Providers::Google::GoogleResponse, response
    assert_equal 'Test response', response.choices.first.to_s
  end

  def test_embedding
    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=test_api_key')
      .to_return(status: 200, body: {
        embedding: {
          values: [0.1, 0.2, 0.3]
        }
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @provider.embedding(model: 'text-embedding-004', input: 'Test input')

    assert_instance_of Durable::Llm::Providers::Google::GoogleEmbeddingResponse, response
    assert_equal [0.1, 0.2, 0.3], response.embedding
  end

  def test_models
    models = @provider.models

    assert_includes models, 'gemini-1.5-flash'
    assert_includes models, 'gemini-1.5-pro'
    assert_includes models, 'text-embedding-004'
  end

  def test_stream
    chunks = [
      { candidates: [{ content: { parts: [{ text: 'Hello' }] } }] },
      { candidates: [{ content: { parts: [{ text: ' world' }] } }] },
      { candidates: [{ content: { parts: [{ text: '!' }] } }] }
    ]

    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:streamGenerateContent?key=test_api_key&alt=sse')
      .to_return(status: 200, body: chunks.map do |chunk|
                   "data: #{chunk.to_json}\n\n"
                 end.join, headers: { 'Content-Type' => 'text/event-stream' })

    streamed_response = ''
    @provider.stream(model: 'gemini-1.5-flash', messages: [{ role: 'user', content: 'Hello' }]) do |chunk|
      streamed_response += chunk.to_s
    end

    assert_equal 'Hello world!', streamed_response
  end

  def test_handle_response_error
    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=test_api_key')
      .to_return(status: 401, body: { error: { message: 'Unauthorized' } }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Durable::Llm::AuthenticationError do
      @provider.completion(model: 'gemini-1.5-flash', messages: [{ role: 'user', content: 'Hello' }])
    end
  end
end
