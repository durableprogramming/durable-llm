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
      # @raise [ArgumentError] If provider_name is nil or empty
      # @raise [NameError] If the provider class cannot be found
      # @example Initialize with OpenAI provider
      #   client = Durable::Llm::Client.new(:openai, model: 'gpt-4', api_key: 'sk-...')
      # @example Initialize with Anthropic provider
      #   client = Durable::Llm::Client.new(:anthropic, model: 'claude-3-opus-20240229')
      def initialize(provider_name, options = {})
        if provider_name.nil? || provider_name.to_s.strip.empty?
          raise ArgumentError, 'provider_name cannot be nil or empty. Supported providers: ' \
                               "#{Durable::Llm::Providers.available_providers.join(', ')}"
        end
        raise ArgumentError, 'options must be a Hash' unless options.is_a?(Hash)

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

      # Performs a text completion with minimal configuration
      #
      # @param text [String] The input text to complete
      # @param opts [Hash] Additional options (currently unused, reserved for future use)
      # @return [String] The generated completion text
      # @raise [ArgumentError] If text is nil or empty
      # @raise [Durable::Llm::APIError] If the API request fails
      # @raise [IndexError] If the response contains no choices
      # @raise [NoMethodError] If the response structure is unexpected
      # @example Text completion with OpenAI
      #   client = Durable::Llm::Client.new(:openai, model: 'gpt-4')
      #   response = client.complete('What is the capital of France?')
      #   puts response # => "The capital of France is Paris."
      def complete(text, _opts = {})
        if text.nil? || text.to_s.strip.empty?
          raise ArgumentError, 'text cannot be nil or empty. Provide a non-empty string for completion.'
        end

        response = completion(process_params(messages: [{ role: 'user', content: text }]))

        choice = response.choices.first
        unless choice
          raise IndexError, 'No completion choices returned from the API. This may indicate an ' \
                            'API error or invalid request parameters.'
        end

        message = choice.message
        unless message
          raise NoMethodError, 'Response choice has no message. The API response format may be ' \
                               'unexpected or the provider may have changed their response structure.'
        end

        content = message.content
        unless content
          raise NoMethodError, 'Response message has no content. This may occur if the model ' \
                               'refused to respond or if content filtering was applied.'
        end

        content
      end
      alias quick_complete complete

      # Performs a completion request
      #
      # @param params [Hash] The completion parameters
      # @option params [String] :model The model to use (overrides default)
      # @option params [Array<Hash>] :messages The conversation messages
      # @option params [Float] :temperature Sampling temperature (0.0-2.0)
      # @option params [Integer] :max_tokens Maximum tokens to generate
      # @return [Object] The completion response object
      # @raise [ArgumentError] If params is not a Hash
      # @raise [Durable::Llm::APIError] If the API request fails
      # @example Perform a completion
      #   client = Durable::Llm::Client.new(:openai, model: 'gpt-4')
      #   response = client.completion(
      #     messages: [
      #       { role: 'system', content: 'You are a helpful assistant.' },
      #       { role: 'user', content: 'Hello!' }
      #     ],
      #     temperature: 0.7
      #   )
      def completion(params = {})
        raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)

        @provider.completion(process_params(params))
      end

      # Performs a chat completion request (alias for completion)
      #
      # @param params [Hash] The chat parameters
      # @option params [String] :model The model to use (overrides default)
      # @option params [Array<Hash>] :messages The conversation messages
      # @option params [Float] :temperature Sampling temperature (0.0-2.0)
      # @option params [Integer] :max_tokens Maximum tokens to generate
      # @return [Object] The chat response object
      # @raise [ArgumentError] If params is not a Hash
      # @raise [Durable::Llm::APIError] If the API request fails
      # @see #completion
      def chat(params = {})
        raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)

        @provider.completion(process_params(params))
      end

      # Performs an embedding request
      #
      # @param params [Hash] The embedding parameters including model and input
      # @option params [String] :model The embedding model to use
      # @option params [String, Array<String>] :input The text(s) to embed
      # @return [Object] The embedding response object
      # @raise [ArgumentError] If params is not a Hash or missing required fields
      # @raise [NotImplementedError] If the provider doesn't support embeddings
      # @raise [Durable::Llm::APIError] If the API request fails
      # @example Generate embeddings
      #   client = Durable::Llm::Client.new(:openai)
      #   response = client.embed(
      #     model: 'text-embedding-ada-002',
      #     input: 'Hello, world!'
      #   )
      def embed(params = {})
        raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)

        @provider.embedding(**process_params(params))
      rescue NotImplementedError
        provider_name = @provider.class.name.split('::').last
        raise NotImplementedError, "#{provider_name} does not support embeddings. " \
                                    'Try using a provider like OpenAI that offers embedding models.'
      end

      # Performs a streaming completion request
      #
      # @param params [Hash] The streaming parameters
      # @option params [String] :model The model to use (overrides default)
      # @option params [Array<Hash>] :messages The conversation messages
      # @option params [Float] :temperature Sampling temperature (0.0-2.0)
      # @option params [Integer] :max_tokens Maximum tokens to generate
      # @yield [Object] Yields stream response chunks as they arrive
      # @return [Object] The final response object
      # @raise [ArgumentError] If params is not a Hash or no block is given
      # @raise [NotImplementedError] If the provider doesn't support streaming
      # @raise [Durable::Llm::APIError] If the API request fails
      # @example Stream a completion
      #   client = Durable::Llm::Client.new(:openai, model: 'gpt-4')
      #   client.stream(messages: [{ role: 'user', content: 'Count to 10' }]) do |chunk|
      #     print chunk.choices.first.delta.content
      #   end
      def stream(params = {}, &block)
        raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)
        unless block_given?
          raise ArgumentError, 'block required for streaming. Use: client.stream(params) { |chunk| ... }'
        end

        @provider.stream(process_params(params), &block)
      rescue NotImplementedError
        provider_name = @provider.class.name.split('::').last
        raise NotImplementedError, "#{provider_name} does not support streaming. " \
                                    'Try using completion() or chat() instead.'
      end

      # Checks if the provider supports streaming
      #
      # @return [Boolean] True if streaming is supported, false otherwise
      def stream?
        @provider.stream?
      end

      # Sets the model for subsequent requests (fluent interface)
      #
      # @param model_name [String] The model to use
      # @return [Client] Returns self for method chaining
      # @example Fluent API usage
      #   client = Durable::Llm::Client.new(:openai)
      #   client.with_model('gpt-4').complete('Hello!')
      def with_model(model_name)
        @model = model_name
        self
      end

      # Sets temperature for the next request (fluent interface)
      #
      # @param temp [Float] The temperature value (0.0-2.0)
      # @return [Client] Returns self for method chaining
      # @example Fluent temperature setting
      #   client.with_temperature(0.7).complete('Be creative!')
      def with_temperature(temp)
        @next_temperature = temp
        self
      end

      # Sets max tokens for the next request (fluent interface)
      #
      # @param tokens [Integer] Maximum tokens to generate
      # @return [Client] Returns self for method chaining
      # @example Fluent max tokens setting
      #   client.with_max_tokens(500).complete('Write a story')
      def with_max_tokens(tokens)
        @next_max_tokens = tokens
        self
      end

      # Creates a copy of the client with different configuration
      #
      # @param options [Hash] New configuration options
      # @option options [String] :model Override the model
      # @return [Client] A new client instance with merged configuration
      # @example Clone with different model
      #   gpt4_client = client.clone_with(model: 'gpt-4')
      #   gpt35_client = client.clone_with(model: 'gpt-3.5-turbo')
      def clone_with(**options)
        provider_name = @provider.class.name.split('::').last.downcase.to_sym
        self.class.new(provider_name, options.merge(model: @model))
      end

      private

      def process_params(opts = {})
        params = default_params.dup.merge(opts)

        # Apply fluent interface settings if present
        params[:temperature] = @next_temperature if @next_temperature
        params[:max_tokens] = @next_max_tokens if @next_max_tokens

        # Clear one-time settings after use
        @next_temperature = nil
        @next_max_tokens = nil

        params
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
