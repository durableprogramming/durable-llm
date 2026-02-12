# frozen_string_literal: true

require 'test_helper'
require 'durable/llm/providers/openai'
require 'durable/llm/providers/anthropic'
require 'durable/llm/providers/groq'
require 'webmock/minitest'

module Durable
  module Llm
    module Providers
      class TestProviderStreaming < Minitest::Test
        def test_openai_streaming
          provider = OpenAI.new(api_key: 'test-key')

          sse_data = <<~SSE
            data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

            data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

            data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

            data: [DONE]

          SSE

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          chunks = []
          provider.stream(model: 'gpt-4', messages: [{ role: 'user', content: 'Hi' }]) do |chunk|
            chunks << chunk
          end

          assert_equal 3, chunks.size
          assert_instance_of OpenAI::OpenAIStreamResponse, chunks.first
          assert_equal '', chunks[0].to_s
          assert_equal 'Hello', chunks[1].to_s
          assert_equal ' world', chunks[2].to_s
        end

        def test_openai_streaming_passes_headers
          provider = OpenAI.new(api_key: 'sk-test123', organization: 'org-test')

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .with(headers: {
                    'Authorization' => 'Bearer sk-test123',
                    'OpenAI-Organization' => 'org-test',
                    'Accept' => 'text/event-stream'
                  })
            .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

          provider.stream(model: 'gpt-4', messages: []) { |_chunk| }

          assert_requested :post, 'https://api.openai.com/v1/chat/completions'
        end

        def test_openai_streaming_passes_stream_param
          provider = OpenAI.new(api_key: 'test-key')

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .with(body: hash_including({ stream: true }))
            .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

          provider.stream(model: 'gpt-4', messages: []) { |_chunk| }

          assert_requested :post, 'https://api.openai.com/v1/chat/completions',
                           body: hash_including({ stream: true })
        end

        def test_anthropic_streaming
          provider = Anthropic.new(api_key: 'test-key')

          sse_data = <<~SSE
            data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[]}}

            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" Claude"}}

            data: {"type":"content_block_stop","index":0}

            data: {"type":"message_stop"}

          SSE

          stub_request(:post, 'https://api.anthropic.com/v1/messages')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          chunks = []
          provider.stream(model: 'claude-3-5-sonnet-20240620', messages: [{ role: 'user', content: 'Hi' }]) do |chunk|
            chunks << chunk
          end

          # Only content_block_delta events should produce non-empty responses
          text_chunks = chunks.select { |c| c.to_s != '' }
          assert_equal 2, text_chunks.size
          assert_equal 'Hello', text_chunks[0].to_s
          assert_equal ' Claude', text_chunks[1].to_s
        end

        def test_anthropic_streaming_with_system_message
          provider = Anthropic.new(api_key: 'test-key')

          stub_request(:post, 'https://api.anthropic.com/v1/messages')
            .with(body: hash_including({
                                         system: 'You are a helpful assistant',
                                         messages: [{ 'role' => 'user', 'content' => 'Hi' }]
                                       }))
            .to_return(status: 200, body: 'data: {"type":"message_stop"}', headers: { 'Content-Type' => 'text/event-stream' })

          provider.stream(
            model: 'claude-3-5-sonnet-20240620',
            messages: [
              { role: 'system', content: 'You are a helpful assistant' },
              { role: 'user', content: 'Hi' }
            ]
          ) { |_chunk| }

          assert_requested :post, 'https://api.anthropic.com/v1/messages',
                           body: hash_including({
                                                  system: 'You are a helpful assistant',
                                                  messages: [{ 'role' => 'user', 'content' => 'Hi' }]
                                                })
        end

        def test_groq_streaming
          provider = Groq.new(api_key: 'test-key')

          sse_data = <<~SSE
            data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":"Fast"},"finish_reason":null}]}

            data: {"id":"chatcmpl-123","choices":[{"index":0,"delta":{"content":" response"},"finish_reason":null}]}

            data: [DONE]

          SSE

          stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          chunks = []
          provider.stream(model: 'mixtral-8x7b-32768', messages: [{ role: 'user', content: 'Hi' }]) do |chunk|
            chunks << chunk
          end

          assert_equal 2, chunks.size
          assert_equal 'Fast', chunks[0].to_s
          assert_equal ' response', chunks[1].to_s
        end

        def test_streaming_with_temperature_conversion
          provider = OpenAI.new(api_key: 'test-key')

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .with(body: hash_including({ 'temperature' => 0.7 }))
            .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

          provider.stream(model: 'gpt-4', messages: [], temperature: 0.7) { |_chunk| }

          assert_requested :post, 'https://api.openai.com/v1/chat/completions',
                           body: hash_including({ 'temperature' => 0.7 })
        end

        def test_streaming_concatenates_chunks_correctly
          provider = OpenAI.new(api_key: 'test-key')

          sse_data = <<~SSE
            data: {"choices":[{"delta":{"content":"The"}}]}

            data: {"choices":[{"delta":{"content":" quick"}}]}

            data: {"choices":[{"delta":{"content":" brown"}}]}

            data: {"choices":[{"delta":{"content":" fox"}}]}

            data: [DONE]

          SSE

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          full_text = ''
          provider.stream(model: 'gpt-4', messages: []) do |chunk|
            full_text += chunk.to_s
          end

          assert_equal 'The quick brown fox', full_text
        end

        def test_streaming_handles_empty_content_deltas
          provider = OpenAI.new(api_key: 'test-key')

          sse_data = <<~SSE
            data: {"choices":[{"delta":{"role":"assistant"}}]}

            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{}}]}

            data: {"choices":[{"delta":{"content":"!"}}]}

            data: [DONE]

          SSE

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          text_parts = []
          provider.stream(model: 'gpt-4', messages: []) do |chunk|
            text_parts << chunk.to_s
          end

          # Should handle empty deltas gracefully
          assert_equal ['', 'Hello', '', '!'], text_parts
        end

        def test_streaming_error_handling
          provider = OpenAI.new(api_key: 'invalid-key')

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 401, body: { error: { message: 'Invalid API key' } }.to_json)

          assert_raises(Durable::Llm::AuthenticationError) do
            provider.stream(model: 'gpt-4', messages: []) { |_chunk| }
          end
        end

        def test_streaming_rate_limit_error
          provider = OpenAI.new(api_key: 'test-key')

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 429, body: { error: { message: 'Rate limit exceeded' } }.to_json)

          assert_raises(Durable::Llm::RateLimitError) do
            provider.stream(model: 'gpt-4', messages: []) { |_chunk| }
          end
        end

        def test_all_streaming_providers_support_stream_class_method
          streaming_providers = [
            OpenAI, Anthropic, Groq,
            Durable::Llm::Providers::Mistral,
            Durable::Llm::Providers::DeepSeek,
            Durable::Llm::Providers::Fireworks
          ]

          streaming_providers.each do |provider_class|
            assert provider_class.stream?, "#{provider_class.name} should support streaming"
          end
        end

        def test_streaming_with_block_parameter
          provider = OpenAI.new(api_key: 'test-key')

          sse_data = 'data: {"choices":[{"delta":{"content":"Test"}}]}' + "\n\n" + 'data: [DONE]'

          stub_request(:post, 'https://api.openai.com/v1/chat/completions')
            .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

          chunk_received = false
          provider.stream(model: 'gpt-4', messages: []) do |chunk|
            chunk_received = true
            assert_instance_of OpenAI::OpenAIStreamResponse, chunk
          end

          assert chunk_received, 'Block should receive chunks'
        end
      end
    end
  end
end
