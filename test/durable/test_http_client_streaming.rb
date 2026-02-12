# frozen_string_literal: true

require 'test_helper'
require 'durable/llm/http_client'
require 'webmock/minitest'

module Durable
  module Llm
    class TestHttpClientStreaming < Minitest::Test
      def setup
        @client = HttpClient.new(url: 'https://api.example.com')
      end

      def test_streaming_supported
        assert @client.streaming_supported?, 'HttpClient should support streaming'
      end

      def test_post_stream_with_successful_response
        # Mock SSE stream response
        sse_data = <<~SSE
          data: {"id":"1","choices":[{"delta":{"content":"Hello"}}]}

          data: {"id":"2","choices":[{"delta":{"content":" world"}}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []

        response = @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.headers['Authorization'] = 'Bearer test-key'
          stream.body = { model: 'gpt-4', messages: [] }
        end

        assert_equal 200, response.status
        assert_equal 2, chunks.size
        assert_equal 'Hello', chunks[0]['choices'][0]['delta']['content']
        assert_equal ' world', chunks[1]['choices'][0]['delta']['content']
      end

      def test_post_stream_filters_done_sentinel
        sse_data = <<~SSE
          data: {"id":"1","choices":[{"delta":{"content":"Test"}}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        assert_equal 1, chunks.size
        assert_equal 'Test', chunks[0]['choices'][0]['delta']['content']
      end

      def test_post_stream_skips_malformed_json
        sse_data = <<~SSE
          data: {"id":"1","choices":[{"delta":{"content":"Valid"}}]}

          data: {malformed json

          data: {"id":"2","choices":[{"delta":{"content":"Also valid"}}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        # Should only get the 2 valid chunks, malformed one is skipped
        assert_equal 2, chunks.size
        assert_equal 'Valid', chunks[0]['choices'][0]['delta']['content']
        assert_equal 'Also valid', chunks[1]['choices'][0]['delta']['content']
      end

      def test_post_stream_handles_empty_chunks
        sse_data = <<~SSE
          data: {"id":"1","choices":[{"delta":{}}]}

          data: {"id":"2","choices":[{"delta":{"content":"Content"}}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        assert_equal 2, chunks.size
        assert_nil chunks[0]['choices'][0]['delta']['content']
        assert_equal 'Content', chunks[1]['choices'][0]['delta']['content']
      end

      def test_post_stream_with_multiple_events_in_single_chunk
        # Simulate multiple SSE events arriving in one TCP chunk
        sse_data = "data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"A\"}}]}\n\ndata: {\"id\":\"2\",\"choices\":[{\"delta\":{\"content\":\"B\"}}]}\n\n"

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        assert_equal 2, chunks.size
        assert_equal 'A', chunks[0]['choices'][0]['delta']['content']
        assert_equal 'B', chunks[1]['choices'][0]['delta']['content']
      end

      def test_post_stream_yields_request_for_configuration
        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

        request_yielded = false
        @client.post_stream('chat/completions') do |stream|
          request_yielded = true
          assert_instance_of HttpClient::StreamRequest, stream
          stream.on_chunk { |_chunk| }
          stream.headers['X-Test'] = 'value'
          stream.body = { test: true }
        end

        assert request_yielded, 'Request should be yielded for configuration'
      end

      def test_post_stream_passes_headers_correctly
        stub_request(:post, 'https://api.example.com/chat/completions')
          .with(headers: { 'Authorization' => 'Bearer secret', 'X-Custom' => 'header' })
          .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |_chunk| }
          stream.headers['Authorization'] = 'Bearer secret'
          stream.headers['X-Custom'] = 'header'
          stream.body = {}
        end

        assert_requested :post, 'https://api.example.com/chat/completions',
                         headers: { 'Authorization' => 'Bearer secret', 'X-Custom' => 'header' }
      end

      def test_post_stream_passes_body_correctly
        request_body = { model: 'gpt-4', messages: [{ role: 'user', content: 'Hi' }], stream: true }

        stub_request(:post, 'https://api.example.com/chat/completions')
          .with(body: request_body.to_json)
          .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |_chunk| }
          stream.body = request_body
        end

        assert_requested :post, 'https://api.example.com/chat/completions',
                         body: request_body.to_json
      end

      def test_post_stream_with_nil_stream_handler
        sse_data = <<~SSE
          data: {"id":"1","choices":[{"delta":{"content":"Test"}}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        # Should not raise error even without stream handler
        response = @client.post_stream('chat/completions') do |stream|
          stream.body = {}
        end

        assert_equal 200, response.status
      end

      def test_post_stream_returns_response_object
        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: 'data: [DONE]', headers: { 'Content-Type' => 'text/event-stream' })

        response = @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |_chunk| }
          stream.body = {}
        end

        assert_instance_of HttpClient::Response, response
        assert_equal 200, response.status
      end

      def test_post_stream_with_anthropic_style_events
        # Anthropic sends different event types
        sse_data = <<~SSE
          data: {"type":"message_start","message":{"id":"msg_1"}}

          data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

          data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

          data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" there"}}

          data: {"type":"content_block_stop","index":0}

          data: {"type":"message_stop"}

        SSE

        stub_request(:post, 'https://api.example.com/v1/messages')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('v1/messages') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        assert_equal 6, chunks.size
        assert_equal 'message_start', chunks[0]['type']
        assert_equal 'content_block_delta', chunks[2]['type']
        assert_equal 'Hello', chunks[2]['delta']['text']
      end

      def test_post_stream_with_real_world_openai_format
        # Real-world OpenAI streaming format
        sse_data = <<~SSE
          data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

          data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

          data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

          data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1694268190,"model":"gpt-4","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

          data: [DONE]

        SSE

        stub_request(:post, 'https://api.example.com/chat/completions')
          .to_return(status: 200, body: sse_data, headers: { 'Content-Type' => 'text/event-stream' })

        chunks = []
        @client.post_stream('chat/completions') do |stream|
          stream.on_chunk { |chunk| chunks << chunk }
          stream.body = {}
        end

        assert_equal 4, chunks.size
        assert_equal 'assistant', chunks[0]['choices'][0]['delta']['role']
        assert_equal 'Hello', chunks[1]['choices'][0]['delta']['content']
        assert_equal '!', chunks[2]['choices'][0]['delta']['content']
        assert_equal 'stop', chunks[3]['choices'][0]['finish_reason']
      end
    end
  end
end
