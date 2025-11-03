# frozen_string_literal: true

# This file serves as the main registry and loader for LLM providers in the Durable gem,
# providing a centralized interface to manage and discover available provider classes. It handles
# automatic loading of provider modules, maintains a dynamic list of registered providers, offers
# utility methods for model discovery and provider resolution based on model IDs, and includes
# provider aliases for backwards compatibility and convenience access.

require 'durable/llm/providers/openai'
require 'durable/llm/providers/anthropic'
require 'durable/llm/providers/cohere'
require 'durable/llm/providers/groq'
require 'durable/llm/providers/huggingface'
require 'durable/llm/providers/azure_openai'
require 'durable/llm/providers/deepseek'
require 'durable/llm/providers/fireworks'
require 'durable/llm/providers/google'
require 'durable/llm/providers/mistral'
require 'durable/llm/providers/opencode'
require 'durable/llm/providers/openrouter'
require 'durable/llm/providers/perplexity'
require 'durable/llm/providers/together'
require 'durable/llm/providers/xai'

module Durable
  module Llm
    # Main module for LLM providers, providing registry and utility methods
    module Providers
      # Loads all provider files in the providers directory.
      #
      # This method dynamically requires all Ruby files in the providers subdirectory,
      # ensuring that all provider classes are loaded and available for use.
      #
      # @return [void]
      def self.load_all
        Dir[File.join(__dir__, 'providers', '*.rb')].sort.each { |file| require file }
      end

      # Returns the provider class for a given provider symbol.
      #
      # This method handles the mapping from provider symbols to their corresponding
      # class constants, including special cases where the symbol doesn't directly
      # map to a capitalized class name.
      #
      # @param provider_sym [Symbol] The provider symbol (e.g., :openai, :anthropic)
      # @return [Class] The provider class
      # @raise [NameError] If the provider class cannot be found
      def self.provider_class_for(provider_sym)
        # Handle special cases where capitalize doesn't match
        case provider_sym
        when :deepseek
          DeepSeek
        when :openrouter
          OpenRouter
        when :azureopenai
          AzureOpenai
        when :opencode
          Opencode
        else
          const_get(provider_sym.to_s.capitalize)
        end
      end

      # Returns a list of all available provider symbols.
      #
      # This method dynamically discovers all provider classes by inspecting the
      # module's constants and filtering for classes that inherit from Base,
      # excluding the Base class itself.
      #
      # @return [Array<Symbol>] Array of provider symbols
      def self.providers
        @providers ||= begin
          provider_classes = constants.select do |const_name|
            const = const_get(const_name)
            next if const.name.split('::').last == 'Base'

            const.is_a?(Class) && const < Durable::Llm::Providers::Base
          end

          provider_classes.map do |const_name|
            const_get(const_name).name.split('::').last.downcase.to_sym
          end.uniq
        end
      end

      # Returns a list of all available provider names as strings.
      #
      # Alias for providers that returns strings instead of symbols, useful for
      # display purposes in error messages and documentation.
      #
      # @return [Array<String>] Array of provider names
      def self.available_providers
        providers.map(&:to_s).sort
      end

      # Returns a flat list of all model IDs across all providers.
      #
      # This method aggregates model IDs from all available providers by calling
      # their models method. If a provider fails to return models (e.g., due to
      # missing API keys), it gracefully handles the error and continues.
      #
      # @return [Array<String>] Array of model IDs
      def self.model_ids
        providers.flat_map do |provider_sym|
          provider_class = provider_class_for(provider_sym)
          begin
            provider_class.models
          rescue StandardError
            []
          end
        end
      end

      # Finds the provider class that supports a given model ID.
      #
      # This method searches through all providers to find which one supports
      # the specified model ID. Returns nil if no provider supports the model.
      #
      # @param model_id [String] The model ID to search for
      # @return [Class, nil] The provider class that supports the model, or nil
      def self.model_id_to_provider(model_id)
        providers.each do |provider_sym|
          provider_class = provider_class_for(provider_sym)
          begin
            return provider_class if provider_class.models.include?(model_id)
          rescue StandardError
            next
          end
        end
        nil
      end

      Openai = OpenAI
      Claude = Anthropic
      Claude3 = Anthropic
      AzureOpenAI = AzureOpenai
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
