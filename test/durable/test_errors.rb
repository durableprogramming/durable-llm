# frozen_string_literal: true

require 'minitest/autorun'
require 'durable/llm/errors'

class TestErrors < Minitest::Test
  def test_error_hierarchy
    # Test that all error classes inherit from the base Error class
    assert_kind_of StandardError, Durable::Llm::Error.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::APIError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::RateLimitError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::AuthenticationError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::InvalidRequestError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::ResourceNotFoundError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::TimeoutError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::ServerError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::UnsupportedProviderError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::ConfigurationError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::ModelNotFoundError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::InsufficientQuotaError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::InvalidResponseError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::NetworkError.new
    assert_kind_of Durable::Llm::Error, Durable::Llm::StreamingError.new
  end

  def test_error_classes_are_exceptions
    # Test that all error classes are proper exceptions
    assert_raises Durable::Llm::APIError do
      raise Durable::Llm::APIError.new('API error')
    end

    assert_raises Durable::Llm::RateLimitError do
      raise Durable::Llm::RateLimitError.new('Rate limit exceeded')
    end

    assert_raises Durable::Llm::AuthenticationError do
      raise Durable::Llm::AuthenticationError.new('Authentication failed')
    end

    assert_raises Durable::Llm::InvalidRequestError do
      raise Durable::Llm::InvalidRequestError.new('Invalid request')
    end

    assert_raises Durable::Llm::ResourceNotFoundError do
      raise Durable::Llm::ResourceNotFoundError.new('Resource not found')
    end

    assert_raises Durable::Llm::TimeoutError do
      raise Durable::Llm::TimeoutError.new('Request timed out')
    end

    assert_raises Durable::Llm::ServerError do
      raise Durable::Llm::ServerError.new('Server error')
    end

    assert_raises Durable::Llm::UnsupportedProviderError do
      raise Durable::Llm::UnsupportedProviderError.new('Unsupported provider')
    end

    assert_raises Durable::Llm::ConfigurationError do
      raise Durable::Llm::ConfigurationError.new('Configuration error')
    end

    assert_raises Durable::Llm::ModelNotFoundError do
      raise Durable::Llm::ModelNotFoundError.new('Model not found')
    end

    assert_raises Durable::Llm::InsufficientQuotaError do
      raise Durable::Llm::InsufficientQuotaError.new('Insufficient quota')
    end

    assert_raises Durable::Llm::InvalidResponseError do
      raise Durable::Llm::InvalidResponseError.new('Invalid response')
    end

    assert_raises Durable::Llm::NetworkError do
      raise Durable::Llm::NetworkError.new('Network error')
    end

    assert_raises Durable::Llm::StreamingError do
      raise Durable::Llm::StreamingError.new('Streaming error')
    end
  end

  def test_error_messages
    # Test that error messages are properly set
    error = Durable::Llm::APIError.new('Test message')
    assert_equal 'Test message', error.message

    error = Durable::Llm::RateLimitError.new('Rate limit hit')
    assert_equal 'Rate limit hit', error.message
  end

  def test_error_inheritance_chain
    # Test that errors can be rescued as the base Error class
    begin
      raise Durable::Llm::APIError.new('API error')
    rescue Durable::Llm::Error => e
      assert_equal 'API error', e.message
      assert_instance_of Durable::Llm::APIError, e
    end

    begin
      raise Durable::Llm::RateLimitError.new('Rate limit')
    rescue Durable::Llm::Error => e
      assert_equal 'Rate limit', e.message
      assert_instance_of Durable::Llm::RateLimitError, e
    end
  end
end
