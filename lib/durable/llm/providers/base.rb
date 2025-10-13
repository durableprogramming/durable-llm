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
      # - default_api_key
      # - completion
      # - models
      # - handle_response
      #
      # Subclasses may override:
      # - stream?
      # - stream
      # - embedding
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
        # @return [Array<String>] The list of available model names
        def self.models
          cache_dir = File.expand_path("#{Dir.home}/.local/durable-llm/cache")

          FileUtils.mkdir_p(cache_dir) unless File.directory?(cache_dir)
          cache_file = File.join(cache_dir, "#{name.split('::').last}.json")

          file_exists = File.exist?(cache_file)
          file_new_enough = file_exists && File.mtime(cache_file) > Time.now - 3600

          if file_exists && file_new_enough
            JSON.parse(File.read(cache_file))
          else
            models = new.models
            File.write(cache_file, JSON.generate(models)) if models.length.positive?
            models
          end
        end

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
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
