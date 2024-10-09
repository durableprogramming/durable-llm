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
