# This file defines a comprehensive hierarchy of custom exception classes for the Durable LLM gem, providing specific error types for different failure scenarios including API errors, rate limiting, authentication issues, network problems, and configuration errors. The error hierarchy extends from a base Error class and allows for precise error handling and user feedback throughout the gem's LLM provider interactions and operations.

module Durable
  module Llm
    class Error < StandardError; end

    class APIError < Error; end

    class RateLimitError < Error; end

    class AuthenticationError < Error; end

    class InvalidRequestError < Error; end

    class ResourceNotFoundError < Error; end

    class TimeoutError < Error; end

    class ServerError < Error; end

    class UnsupportedProviderError < Error; end

    class ConfigurationError < Error; end

    class ModelNotFoundError < Error; end

    class InsufficientQuotaError < Error; end

    class InvalidResponseError < Error; end

    class NetworkError < Error; end

    class StreamingError < Error; end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
