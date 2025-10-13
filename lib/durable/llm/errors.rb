# frozen_string_literal: true

# This file defines a comprehensive hierarchy of custom exception classes for the Durable LLM gem,
# providing specific error types for different failure scenarios including API errors, rate limiting,
# authentication issues, network problems, and configuration errors. The error hierarchy extends
# from a base Error class and allows for precise error handling and user feedback throughout the
# gem's LLM provider interactions and operations.

module Durable
  module Llm
    # Base error class for all Durable LLM exceptions.
    #
    # All custom errors in the Durable LLM gem inherit from this class,
    # allowing users to rescue all LLM-related errors with a single catch block.
    #
    # @example Rescuing all Durable LLM errors
    #   begin
    #     # LLM operation
    #   rescue Durable::Llm::Error => e
    #     puts "LLM operation failed: #{e.message}"
    #   end
    class Error < StandardError; end

    # Error raised when an API request fails with an unexpected error.
    #
    # This error is raised for API errors that don't fit into more specific categories
    # like authentication, rate limiting, or server errors.
    #
    # @example Handling API errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::APIError => e
    #     puts "API request failed: #{e.message}"
    #   end
    class APIError < Error; end

    # Error raised when the API rate limit has been exceeded.
    #
    # This typically occurs when too many requests are made within a short time period.
    # Users should implement retry logic with exponential backoff when encountering this error.
    #
    # @example Handling rate limit errors with retry
    #   retries = 0
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::RateLimitError => e
    #     if retries < 3
    #       sleep(2 ** retries)
    #       retries += 1
    #       retry
    #     else
    #       puts "Rate limit exceeded after retries: #{e.message}"
    #     end
    #   end
    class RateLimitError < Error; end

    # Error raised when authentication with the LLM provider fails.
    #
    # This typically occurs when API keys are invalid, expired, or not provided.
    # Users should check their API key configuration when encountering this error.
    #
    # @example Handling authentication errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::AuthenticationError => e
    #     puts "Authentication failed. Please check your API key: #{e.message}"
    #   end
    class AuthenticationError < Error; end

    # Error raised when the request parameters are invalid.
    #
    # This occurs when the request contains malformed data, invalid parameters,
    # or violates the API's constraints.
    #
    # @example Handling invalid request errors
    #   begin
    #     client.complete("Hello", model: "invalid-model")
    #   rescue Durable::Llm::InvalidRequestError => e
    #     puts "Invalid request parameters: #{e.message}"
    #   end
    class InvalidRequestError < Error; end

    # Error raised when a requested resource cannot be found.
    #
    # This typically occurs when requesting a model or resource that doesn't exist
    # or is not available to the user.
    #
    # @example Handling resource not found errors
    #   begin
    #     client.complete("Hello", model: "nonexistent-model")
    #   rescue Durable::Llm::ResourceNotFoundError => e
    #     puts "Requested resource not found: #{e.message}"
    #   end
    class ResourceNotFoundError < Error; end

    # Error raised when a request times out.
    #
    # This occurs when the API request takes longer than the configured timeout period.
    # Users may want to increase timeout settings or retry the request.
    #
    # @example Handling timeout errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::TimeoutError => e
    #     puts "Request timed out: #{e.message}"
    #   end
    class TimeoutError < Error; end

    # Error raised when the LLM provider's server encounters an internal error.
    #
    # This indicates a problem on the provider's side, not with the user's request.
    # Users should retry the request after a short delay.
    #
    # @example Handling server errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::ServerError => e
    #     puts "Server error occurred: #{e.message}"
    #     # Consider retrying after a delay
    #   end
    class ServerError < Error; end

    # Error raised when attempting to use an unsupported LLM provider.
    #
    # This occurs when the requested provider is not implemented or configured
    # in the Durable LLM gem.
    #
    # @example Handling unsupported provider errors
    #   begin
    #     client = Durable::Llm::Client.new(provider: "unsupported-provider")
    #   rescue Durable::Llm::UnsupportedProviderError => e
    #     puts "Unsupported provider: #{e.message}"
    #   end
    class UnsupportedProviderError < Error; end

    # Error raised when there is a configuration problem.
    #
    # This occurs when required configuration is missing, invalid, or inconsistent.
    # Users should check their configuration settings.
    #
    # @example Handling configuration errors
    #   begin
    #     client = Durable::Llm::Client.new(api_key: nil)
    #   rescue Durable::Llm::ConfigurationError => e
    #     puts "Configuration error: #{e.message}"
    #   end
    class ConfigurationError < Error; end

    # Error raised when the requested model is not found or not available.
    #
    # This is similar to ResourceNotFoundError but specifically for models.
    # It occurs when the specified model doesn't exist or isn't accessible.
    #
    # @example Handling model not found errors
    #   begin
    #     client.complete("Hello", model: "unknown-model")
    #   rescue Durable::Llm::ModelNotFoundError => e
    #     puts "Model not found: #{e.message}"
    #   end
    class ModelNotFoundError < Error; end

    # Error raised when the account has insufficient quota or credits.
    #
    # This occurs when the user's account has exhausted its usage limits
    # or doesn't have enough credits for the requested operation.
    #
    # @example Handling insufficient quota errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::InsufficientQuotaError => e
    #     puts "Insufficient quota: #{e.message}"
    #   end
    class InsufficientQuotaError < Error; end

    # Error raised when the API response is invalid or malformed.
    #
    # This occurs when the provider returns a response that cannot be parsed
    # or doesn't match the expected format.
    #
    # @example Handling invalid response errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::InvalidResponseError => e
    #     puts "Invalid response received: #{e.message}"
    #   end
    class InvalidResponseError < Error; end

    # Error raised when there is a network connectivity problem.
    #
    # This occurs when the request cannot reach the LLM provider due to
    # network issues, DNS problems, or connectivity failures.
    #
    # @example Handling network errors
    #   begin
    #     client.complete("Hello")
    #   rescue Durable::Llm::NetworkError => e
    #     puts "Network error: #{e.message}"
    #   end
    class NetworkError < Error; end

    # Error raised when there is a problem with streaming responses.
    #
    # This occurs during streaming operations when the connection is interrupted,
    # the stream format is invalid, or other streaming-specific issues arise.
    #
    # @example Handling streaming errors
    #   begin
    #     client.stream("Hello") do |chunk|
    #       puts chunk
    #     end
    #   rescue Durable::Llm::StreamingError => e
    #     puts "Streaming error: #{e.message}"
    #   end
    class StreamingError < Error; end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
