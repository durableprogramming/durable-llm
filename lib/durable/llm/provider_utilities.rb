# frozen_string_literal: true

# This module provides utility functions for working with LLM providers, including
# provider discovery, comparison, and model routing capabilities. It helps developers
# choose and switch between providers efficiently.

module Durable
  module Llm
    # Utility methods for provider management and comparison
    #
    # This module offers helper methods for:
    # - Discovering available providers
    # - Finding providers that support specific models
    # - Comparing provider capabilities
    # - Routing requests to appropriate providers
    #
    # @example Find provider for a model
    #   provider = ProviderUtilities.provider_for_model('gpt-4')
    #   # => :openai
    module ProviderUtilities
      module_function

      # Lists all available providers
      #
      # @return [Array<Symbol>] Array of provider names
      # @example List providers
      #   providers = ProviderUtilities.available_providers
      #   # => [:openai, :anthropic, :google, ...]
      def available_providers
        Providers.available_providers
      end

      # Finds the provider that supports a given model
      #
      # @param model_id [String] The model identifier
      # @return [Symbol, nil] The provider name or nil if not found
      # @example Find provider for GPT-4
      #   provider = ProviderUtilities.provider_for_model('gpt-4')
      #   # => :openai
      # @example Find provider for Claude
      #   provider = ProviderUtilities.provider_for_model('claude-3-opus-20240229')
      #   # => :anthropic
      def provider_for_model(model_id)
        Providers.model_id_to_provider(model_id)
      end

      # Gets all models available for a provider
      #
      # @param provider_name [Symbol, String] The provider name
      # @param options [Hash] Provider configuration options
      # @return [Array<String>] Array of model IDs
      # @example Get OpenAI models
      #   models = ProviderUtilities.models_for_provider(:openai)
      def models_for_provider(provider_name, **options)
        Durable::Llm.models(provider_name, **options)
      rescue StandardError
        []
      end

      # Checks if a provider supports a specific capability
      #
      # @param provider_name [Symbol, String] The provider name
      # @param capability [Symbol] The capability to check (:streaming, :embeddings, :chat)
      # @return [Boolean] True if capability is supported
      # @example Check streaming support
      #   supports = ProviderUtilities.supports_capability?(:openai, :streaming)
      #   # => true
      def supports_capability?(provider_name, capability)
        provider_class = Providers.provider_class_for(provider_name)
        instance = provider_class.new

        case capability
        when :streaming
          instance.respond_to?(:stream?) && instance.stream?
        when :embeddings
          instance.respond_to?(:embedding)
        when :chat, :completion
          instance.respond_to?(:completion)
        else
          false
        end
      rescue StandardError
        false
      end

      # Finds all providers that support a specific capability
      #
      # @param capability [Symbol] The capability to filter by
      # @return [Array<Symbol>] Providers supporting the capability
      # @example Find streaming providers
      #   providers = ProviderUtilities.providers_with_capability(:streaming)
      #   # => [:openai, :anthropic, :google, ...]
      def providers_with_capability(capability)
        available_providers.select do |provider|
          supports_capability?(provider, capability)
        end
      end

      # Compares models across providers based on common characteristics
      #
      # @param model_ids [Array<String>] Models to compare
      # @return [Hash] Comparison data
      # @example Compare models
      #   comparison = ProviderUtilities.compare_models(['gpt-4', 'claude-3-opus-20240229'])
      def compare_models(model_ids)
        model_ids.map do |model_id|
          provider = provider_for_model(model_id)
          {
            model: model_id,
            provider: provider,
            streaming: provider ? supports_capability?(provider, :streaming) : false
          }
        end
      end

      # Creates a fallback chain of providers for redundancy
      #
      # This method helps build resilient systems by providing fallback options
      # when a primary provider is unavailable.
      #
      # @param providers [Array<Symbol>] Ordered list of providers to try
      # @param options [Hash] Configuration options
      # @return [Array<Durable::Llm::Client>] Array of clients in fallback order
      # @example Create fallback chain
      #   clients = ProviderUtilities.fallback_chain(
      #     [:openai, :anthropic, :google],
      #     model_map: {
      #       openai: 'gpt-4',
      #       anthropic: 'claude-3-opus-20240229',
      #       google: 'gemini-pro'
      #     }
      #   )
      def fallback_chain(providers, options = {})
        model_map = options[:model_map] || {}

        providers.map do |provider|
          model = model_map[provider]
          Durable::Llm.new(provider, model: model)
        rescue StandardError => e
          warn "Failed to create client for #{provider}: #{e.message}"
          nil
        end.compact
      end

      # Executes a completion with automatic provider fallback
      #
      # @param text [String] The input text
      # @param providers [Array<Symbol>] Ordered providers to try
      # @param model_map [Hash] Map of provider to model
      # @return [String, nil] The completion text or nil if all fail
      # @example Completion with fallback
      #   result = ProviderUtilities.complete_with_fallback(
      #     'Hello!',
      #     providers: [:openai, :anthropic],
      #     model_map: { openai: 'gpt-4', anthropic: 'claude-3-opus-20240229' }
      #   )
      def complete_with_fallback(text, providers:, model_map: {})
        providers.each do |provider|
          begin
            client = Durable::Llm.new(provider, model: model_map[provider])
            return client.complete(text)
          rescue StandardError => e
            warn "Provider #{provider} failed: #{e.message}"
            next
          end
        end

        nil # All providers failed
      end

      # Gets provider information including capabilities
      #
      # @param provider_name [Symbol, String] The provider name
      # @return [Hash] Provider information
      # @example Get provider info
      #   info = ProviderUtilities.provider_info(:openai)
      #   # => { name: :openai, streaming: true, embeddings: true, ... }
      def provider_info(provider_name)
        {
          name: provider_name,
          streaming: supports_capability?(provider_name, :streaming),
          embeddings: supports_capability?(provider_name, :embeddings),
          chat: supports_capability?(provider_name, :chat)
        }
      rescue StandardError => e
        { name: provider_name, error: e.message }
      end

      # Lists all providers with their capabilities
      #
      # @return [Array<Hash>] Array of provider information hashes
      # @example List all provider capabilities
      #   all = ProviderUtilities.all_provider_info
      def all_provider_info
        available_providers.map { |p| provider_info(p) }
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
