# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/http_client'
require 'ostruct'

class TestHttpClient < Minitest::Test
  def setup
    @base_url = 'https://api.example.com'
    @client = Durable::Llm::HttpClient.new(url: @base_url)
  end

  def test_initialize_sets_base_url
    assert_equal @base_url, @client.instance_variable_get(:@base_url)
  end

  def test_initialize_creates_faraday_connection
    conn = @client.instance_variable_get(:@conn)
    assert_instance_of Faraday::Connection, conn
  end

  def test_response_wraps_faraday_response
    faraday_response = OpenStruct.new(status: 200, body: { message: 'success' })
    response = Durable::Llm::HttpClient::Response.new(faraday_response)

    assert_equal 200, response.status
    assert_equal({ message: 'success' }, response.body)
  end

  def test_post_with_headers_and_body
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    mock_request = mock('request')
    mock_request.stubs(:headers).returns({})
    mock_request.stubs(:body=)
    mock_request.stubs(:options).returns(OpenStruct.new)

    stub_conn.expects(:post).with('/test').yields(mock_request).returns(
      OpenStruct.new(status: 200, body: { result: 'ok' })
    )

    response = @client.post('/test') do |req|
      req.headers['Authorization'] = 'Bearer token'
      req.body = { data: 'test' }
    end

    assert_equal 200, response.status
    assert_equal({ result: 'ok' }, response.body)
  end

  def test_get_with_headers
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    mock_request = mock('request')
    mock_request.stubs(:headers).returns({})

    stub_conn.expects(:get).with('/models').yields(mock_request).returns(
      OpenStruct.new(status: 200, body: { models: ['model1', 'model2'] })
    )

    response = @client.get('/models') do |req|
      req.headers['Authorization'] = 'Bearer token'
    end

    assert_equal 200, response.status
    assert_equal({ models: ['model1', 'model2'] }, response.body)
  end

  def test_streaming_supported_returns_true
    assert @client.streaming_supported?
  end

  def test_request_class_initialization
    conn = mock('connection')
    request = Durable::Llm::HttpClient::Request.new(conn, '/path')

    assert_equal({}, request.headers)
    assert_nil request.body
    assert_instance_of Durable::Llm::HttpClient::RequestOptions, request.options
  end

  def test_stream_request_initialization
    conn = mock('connection')
    stream_request = Durable::Llm::HttpClient::StreamRequest.new(conn, '/path')

    assert_equal({}, stream_request.headers)
    assert_nil stream_request.body
    assert_nil stream_request.chunk_handler
  end

  def test_stream_request_on_chunk
    conn = mock('connection')
    stream_request = Durable::Llm::HttpClient::StreamRequest.new(conn, '/path')

    handler = proc { |chunk| chunk }
    result = stream_request.on_chunk(&handler)

    assert_equal handler, stream_request.chunk_handler
    assert_equal stream_request, result # Test fluent interface
  end

  def test_request_options_initialization
    conn = mock('connection')
    options = Durable::Llm::HttpClient::RequestOptions.new(conn)

    assert_nil options.on_data
  end

  def test_post_stream_raises_if_not_supported
    @client.stubs(:streaming_supported?).returns(false)
    @client.stubs(:respond_to?).with(:streaming_supported?).returns(true)

    error = assert_raises(NotImplementedError) do
      @client.post_stream('/stream') {}
    end

    assert_match(/does not support streaming/, error.message)
  end

  def test_post_stream_handles_unauthorized_error
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    error_body = { error: 'Unauthorized' }
    faraday_error = Faraday::UnauthorizedError.new('Unauthorized')
    faraday_error.stubs(:response_body).returns(error_body)

    stub_conn.expects(:post).raises(faraday_error)

    response = @client.post_stream('/stream') do |stream|
      stream.headers['Authorization'] = 'Bearer invalid'
      stream.body = { test: true }
    end

    assert_equal 401, response.status
    assert_equal error_body, response.body
  end

  def test_post_stream_handles_rate_limit_error
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    error_body = { error: 'Rate limit exceeded' }
    faraday_error = Faraday::TooManyRequestsError.new('Too Many Requests')
    faraday_error.stubs(:response_body).returns(error_body)

    stub_conn.expects(:post).raises(faraday_error)

    response = @client.post_stream('/stream') do |stream|
      stream.headers['Authorization'] = 'Bearer token'
      stream.body = { test: true }
    end

    assert_equal 429, response.status
    assert_equal error_body, response.body
  end

  def test_post_stream_handles_client_error
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    error_body = { error: 'Bad request' }
    faraday_error = Faraday::ClientError.new('Bad Request')
    faraday_error.stubs(:response_status).returns(400)
    faraday_error.stubs(:response_body).returns(error_body)

    stub_conn.expects(:post).raises(faraday_error)

    response = @client.post_stream('/stream') do |stream|
      stream.headers['Authorization'] = 'Bearer token'
      stream.body = { invalid: true }
    end

    assert_equal 400, response.status
    assert_equal error_body, response.body
  end

  def test_post_stream_handles_server_error
    stub_conn = mock('faraday_connection')
    @client.instance_variable_set(:@conn, stub_conn)

    error_body = { error: 'Internal server error' }
    faraday_error = Faraday::ServerError.new('Server Error')
    faraday_error.stubs(:response_status).returns(500)
    faraday_error.stubs(:response_body).returns(error_body)

    stub_conn.expects(:post).raises(faraday_error)

    response = @client.post_stream('/stream') do |stream|
      stream.headers['Authorization'] = 'Bearer token'
      stream.body = { test: true }
    end

    assert_equal 500, response.status
    assert_equal error_body, response.body
  end

  def test_try_parse_json_with_valid_json
    json_string = '{"key": "value"}'
    result = @client.send(:try_parse_json, json_string)

    assert_equal({ 'key' => 'value' }, result)
  end

  def test_try_parse_json_with_invalid_json
    invalid_string = 'not json'
    result = @client.send(:try_parse_json, invalid_string)

    assert_equal 'not json', result
  end

  def test_try_parse_json_with_empty_string
    result = @client.send(:try_parse_json, '')

    assert_equal '', result
  end
end
