# frozen_string_literal: true

# This file implements the main Client class that provides a unified interface for interacting
# with different LLM providers. It acts as a facade that delegates operations like completion,
# chat, embedding, and streaming to the appropriate provider instance while handling parameter
# processing, model configuration, and providing convenience methods for quick text completion.
# The client automatically resolves provider classes based on the provider name and manages
# default parameters including model selection.

require 'zeitwerk'
require 'durable/llm/providers'

module Durable
  module Llm
    # Unified interface for interacting with different LLM providers
    #
    # The Client class provides a facade that delegates operations like completion, chat,
    # embedding, and streaming to the appropriate provider instance while handling parameter
    # processing, model configuration, and providing convenience methods for quick text completion.
    # The client automatically resolves provider classes based on the provider name and manages
    # default parameters including model selection.
    class Client
      # @return [Object] The underlying provider instance
      attr_reader :provider

      # @return [String, nil] The default model to use for requests
      attr_accessor :model

      # Initializes a new LLM client for the specified provider
      #
      # @param provider_name [Symbol, String] The name of the LLM provider (e.g., :openai, :anthropic)
      # @param options [Hash] Configuration options for the provider and client
      # @option options [String] :model The default model to use for requests
      # @option options [String] 'model' Alternative string key for model
      # @option options [String] :api_key API key for authentication (provider-specific)
      # @raise [NameError] If the provider class cannot be found
      def initialize(provider_name, options = {})
        @model = options.delete('model') || options.delete(:model) if options.key?('model') || options.key?(:model)

        provider_class = Durable::Llm::Providers.provider_class_for(provider_name)

        @provider = provider_class.new(**options)
      end

      # Returns the default parameters to merge with request options
      #
      # @return [Hash] Default parameters including model if set
      def default_params
        @model ? { model: @model } : {}
      end

      # Performs a quick text completion with minimal configuration
      #
      # @param text [String] The input text to complete
      # @param opts [Hash] Additional options (currently unused, reserved for future use)
      # @return [String] The generated completion text
      # @raise [Durable::Llm::APIError] If the API request fails
      # @raise [IndexError] If the response contains no choices
      # @raise [NoMethodError] If the response structure is unexpected
      def quick_complete(text, _opts = {})
        response = completion(process_params(messages: [{ role: 'user', content: text }]))

        choice = response.choices.first
        raise IndexError, 'No completion choices returned' unless choice

        message = choice.message
        raise NoMethodError, 'Response choice has no message' unless message

        content = message.content
        raise NoMethodError, 'Response message has no content' unless content

        content
      end

      # Performs a completion request
      #
      # @param params [Hash] The completion parameters
      # @return [Object] The completion response object
      # @raise [Durable::Llm::APIError] If the API request fails
      def completion(params = {})
        @provider.completion(process_params(params))
      end

      # Performs a chat completion request (alias for completion)
      #
      # @param params [Hash] The chat parameters
      # @return [Object] The chat response object
      # @raise [Durable::Llm::APIError] If the API request fails
      def chat(params = {})
        @provider.completion(process_params(params))
      end

      # Performs an embedding request
      #
      # @param params [Hash] The embedding parameters including model and input
      # @return [Object] The embedding response object
      # @raise [NotImplementedError] If the provider doesn't support embeddings
      # @raise [Durable::Llm::APIError] If the API request fails
      def embed(params = {})
        @provider.embedding(**process_params(params))
      rescue NotImplementedError
        raise NotImplementedError, "#{@provider.class.name} does not support embeddings"
      end

      # Performs a streaming completion request
      #
      # @param params [Hash] The streaming parameters
      # @yield [Object] Yields stream response chunks as they arrive
      # @return [Object] The final response object
      # @raise [NotImplementedError] If the provider doesn't support streaming
      # @raise [Durable::Llm::APIError] If the API request fails
      def stream(params = {}, &block)
        @provider.stream(process_params(params), &block)
      rescue NotImplementedError
        raise NotImplementedError, "#{@provider.class.name} does not support streaming"
      end

      # Checks if the provider supports streaming
      #
      # @return [Boolean] True if streaming is supported, false otherwise
      def stream?
        @provider.stream?
      end

      private

      def process_params(opts = {})
        default_params.dup.merge(opts)
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
