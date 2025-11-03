# frozen_string_literal: true

require 'json'
require 'fileutils'

# This file defines the abstract base class for all LLM providers in the Durable gem,
# establishing a common interface and shared functionality that all provider implementations
# must follow. It defines required methods like completion, models, and streaming capabilities,
# provides caching mechanisms for model lists, handles default API key resolution, and includes
# stub implementations for optional features like embeddings. The base class ensures consistency
# across different LLM providers while allowing each provider to implement their specific API
# communication patterns and response handling.

module Durable
  module Llm
    module Providers
      # Abstract base class for all LLM providers
      #
      # This class defines the common interface that all LLM provider implementations must follow.
      # It provides default implementations for caching model lists, handling API keys, and stub
      # implementations for optional features.
      #
      # Subclasses must implement the following methods:
      # - {#default_api_key} - Returns the default API key from configuration
      # - {#completion} - Performs a completion request
      # - {#models} - Returns list of available models
      # - {#handle_response} - Processes API responses
      #
      # Subclasses may optionally override:
      # - {#stream?} - Check if streaming is supported
      # - {#stream} - Perform streaming requests
      # - {#embedding} - Generate embeddings
      #
      # @abstract Subclass and implement required methods
      # @example Implementing a custom provider
      #   class MyProvider < Durable::Llm::Providers::Base
      #     def default_api_key
      #       Durable::Llm.configuration.my_provider&.api_key ||
      #         ENV['MY_PROVIDER_API_KEY']
      #     end
      #
      #     def completion(options)
      #       # Make API request
      #       response = make_request(options)
      #       handle_response(response)
      #     end
      #
      #     def models
      #       ['model-1', 'model-2']
      #     end
      #
      #     private
      #
      #     def handle_response(response)
      #       # Process and return response
      #     end
      #   end
      class Base
        # @return [String, nil] The default API key for this provider, or nil if not configured
        # @raise [NotImplementedError] Subclasses must implement this method
        def default_api_key
          raise NotImplementedError, 'Subclasses must implement default_api_key'
        end

        # @!attribute [rw] api_key
        #   @return [String, nil] The API key used for authentication
        attr_accessor :api_key

        # Initializes a new provider instance
        #
        # @param api_key [String, nil] The API key to use for authentication. If nil, uses default_api_key
        # @example Initialize with explicit API key
        #   provider = Durable::Llm::Providers::OpenAI.new(api_key: 'sk-...')
        # @example Initialize with default API key from configuration
        #   provider = Durable::Llm::Providers::OpenAI.new
        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
        end

        # Performs a completion request
        #
        # @param options [Hash] The completion options including model, messages, etc.
        # @return [Object] The completion response object
        # @raise [NotImplementedError] Subclasses must implement this method
        def completion(options)
          raise NotImplementedError, 'Subclasses must implement completion'
        end

        # Retrieves the list of available models, with caching
        #
        # Models are cached in `~/.local/durable-llm/cache/` for 1 hour to reduce
        # API calls. The cache is automatically refreshed after expiration.
        #
        # @return [Array<String>] The list of available model names
        # @example Get available models for OpenAI
        #   models = Durable::Llm::Providers::OpenAI.models
        #   # => ["gpt-4", "gpt-3.5-turbo", ...]
        def self.models
          cache_file = model_cache_file
          return cached_models(cache_file) if cache_valid?(cache_file)

          fetch_and_cache_models(cache_file)
        end

        # Returns the path to the model cache file
        #
        # @return [String] The cache file path
        def self.model_cache_file
          cache_dir = File.expand_path("#{Dir.home}/.local/durable-llm/cache")
          FileUtils.mkdir_p(cache_dir) unless File.directory?(cache_dir)
          File.join(cache_dir, "#{name.split('::').last}.json")
        end

        # Checks if the cache file is valid (exists and not expired)
        #
        # @param cache_file [String] The cache file path
        # @return [Boolean] True if cache is valid, false otherwise
        def self.cache_valid?(cache_file)
          File.exist?(cache_file) && File.mtime(cache_file) > Time.now - 3600
        end

        # Reads models from cache file
        #
        # @param cache_file [String] The cache file path
        # @return [Array<String>] The cached model names
        def self.cached_models(cache_file)
          JSON.parse(File.read(cache_file))
        end

        # Fetches models from API and caches them
        #
        # @param cache_file [String] The cache file path
        # @return [Array<String>] The fetched model names
        def self.fetch_and_cache_models(cache_file)
          models = new.models
          File.write(cache_file, JSON.generate(models)) if models.length.positive?
          models
        end

        private_class_method :model_cache_file, :cache_valid?, :cached_models, :fetch_and_cache_models

        # Returns the list of supported option names for completions
        #
        # @return [Array<String>] The supported option names
        def self.options
          %w[temperature max_tokens top_p frequency_penalty presence_penalty]
        end

        # Retrieves the list of available models for this provider instance
        #
        # @return [Array<String>] The list of available model names
        # @raise [NotImplementedError] Subclasses must implement this method
        def models
          raise NotImplementedError, 'Subclasses must implement models'
        end

        # Checks if this provider class supports streaming
        #
        # @return [Boolean] True if streaming is supported, false otherwise
        def self.stream?
          false
        end

        # Checks if this provider instance supports streaming
        #
        # @return [Boolean] True if streaming is supported, false otherwise
        def stream?
          self.class.stream?
        end

        # Performs a streaming completion request
        #
        # @param options [Hash] The stream options including model, messages, etc.
        # @yield [Object] Yields stream response chunks as they arrive
        # @return [Object] The final response object
        # @raise [NotImplementedError] Subclasses must implement this method
        def stream(options, &block)
          raise NotImplementedError, 'Subclasses must implement stream'
        end

        # Performs an embedding request
        #
        # @param model [String] The model to use for generating embeddings
        # @param input [String, Array<String>] The input text(s) to embed
        # @param options [Hash] Additional options for the embedding request
        # @return [Object] The embedding response object
        # @raise [NotImplementedError] Subclasses must implement this method
        def embedding(model:, input:, **options)
          raise NotImplementedError, 'Subclasses must implement embedding'
        end

        private

        # Handles the raw response from the API, processing errors and returning normalized response
        #
        # @param response [Object] The raw response from the API call
        # @return [Object] The processed response object
        # @raise [Durable::Llm::APIError] If the response indicates an API error
        # @raise [NotImplementedError] Subclasses must implement this method
        def handle_response(response)
          raise NotImplementedError, 'Subclasses must implement handle_response'
        end

        # Validates that required parameters are present in the options hash
        #
        # @param options [Hash] The options hash to validate
        # @param required_params [Array<Symbol, String>] List of required parameter names
        # @raise [ArgumentError] If any required parameters are missing or empty
        # @return [void]
        # @example Validate completion parameters
        #   validate_required_params(options, [:model, :messages])
        def validate_required_params(options, required_params)
          missing = required_params.select do |param|
            value = options[param] || options[param.to_s]
            value.nil? || (value.respond_to?(:empty?) && value.empty?)
          end

          return if missing.empty?

          raise ArgumentError, "Missing required parameters: #{missing.join(', ')}. " \
                               "Please provide these parameters in your request."
        end

        # Validates that a parameter is within a specified range
        #
        # @param value [Numeric] The value to validate
        # @param param_name [String, Symbol] The parameter name for error messages
        # @param min [Numeric] The minimum allowed value (inclusive)
        # @param max [Numeric] The maximum allowed value (inclusive)
        # @raise [ArgumentError] If the value is outside the allowed range
        # @return [void]
        # @example Validate temperature parameter
        #   validate_range(options[:temperature], :temperature, 0.0, 2.0)
        def validate_range(value, param_name, min, max)
          return if value.nil? # Allow nil values (will use provider defaults)
          return if value >= min && value <= max

          raise ArgumentError, "#{param_name} must be between #{min} and #{max}, got #{value}"
        end

        # Validates that the API key is configured
        #
        # @raise [Durable::Llm::AuthenticationError] If API key is not configured
        # @return [void]
        # @example Validate API key before making request
        #   validate_api_key
        def validate_api_key
          return unless @api_key.nil? || @api_key.to_s.strip.empty?

          provider_name = self.class.name.split('::').last
          raise Durable::Llm::AuthenticationError,
                "API key not configured for #{provider_name}. " \
                "Set it via Durable::Llm.configure or environment variable."
        end

        # Sanitizes and normalizes request options
        #
        # @param options [Hash] The raw options hash
        # @return [Hash] The sanitized options with string keys converted to symbols
        # @example Sanitize options
        #   sanitized = sanitize_options({ 'model' => 'gpt-4', 'temperature' => 0.7 })
        #   # => { model: 'gpt-4', temperature: 0.7 }
        def sanitize_options(options)
          return {} if options.nil?

          options.transform_keys(&:to_sym)
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
