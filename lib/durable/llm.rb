# frozen_string_literal: true

# Main entry point for the Durable::Llm module.
#
# This module provides a unified interface for interacting with multiple Large Language Model (LLM)
# providers through a consistent API. It handles configuration management, provider instantiation,
# and offers convenience methods for common LLM operations.
#
# The module uses Zeitwerk for efficient autoloading of its components and maintains a global
# configuration that can be customized through environment variables or programmatic setup.
#
# ## Basic Usage
#
# ```ruby
# require 'durable/llm'
#
# # Configure API keys
# Durable::Llm.configure do |config|
#   config.openai.api_key = 'your-openai-key'
# end
#
# # Create a client and make a request
# client = Durable::Llm.new(:openai, model: 'gpt-4')
# response = client.complete('Hello, world!')
# puts response # => "Hello! How can I help you today?"
# ```
#
# ## Configuration
#
# Configuration can be done via environment variables using the `DLLM__` prefix:
#
# ```bash
# export DLLM__OPENAI__API_KEY=your-key-here
# export DLLM__ANTHROPIC__API_KEY=your-anthropic-key
# ```
#
# Or programmatically:
#
# ```ruby
# Durable::Llm.configure do |config|
#   config.openai.api_key = 'your-key'
#   config.anthropic.api_key = 'your-anthropic-key'
#   config.default_provider = 'anthropic'
# end
# ```
#
# ## Supported Providers
#
# - OpenAI (GPT models)
# - Anthropic (Claude models)
# - Google (Gemini models)
# - Cohere
# - Mistral AI
# - Groq
# - Fireworks AI
# - Together AI
# - DeepSeek
# - OpenRouter
# - Perplexity
# - xAI
# - Azure OpenAI
#
# @see Durable::Llm::Client For the main client interface
# @see Durable::Llm::Configuration For configuration options
# @see Durable::Llm::Providers For available providers

require 'zeitwerk'
loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, '.rb')
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.push_dir("#{File.dirname(__FILE__)}/..")

require 'durable/llm/configuration'
require 'durable/llm/version'

module Durable
  # The Llm module provides a unified interface for Large Language Model operations.
  #
  # This module serves as the main entry point for the Durable LLM gem, offering:
  # - Global configuration management
  # - Provider-agnostic client creation
  # - Convenience methods for common operations
  # - Access to version information
  #
  # The module maintains a singleton configuration instance that can be customized
  # to set API keys, default providers, and other global settings.
  #
  # @example Basic setup and usage
  #   Durable::Llm.configure do |config|
  #     config.openai.api_key = 'sk-...'
  #   end
  #
  #   client = Durable::Llm.new(:openai)
  #   response = client.complete('Hello!')
  #
  # @see Durable::Llm::Client
  # @see Durable::Llm::Configuration
  module Llm
    class << self
      # @return [Configuration] The global configuration instance
      attr_accessor :configuration

      # Returns the current configuration instance.
      #
      # This is an alias for the configuration accessor, provided for convenience.
      #
      # @return [Configuration] The global configuration instance
      # @see #configuration
      def config
        configuration
      end

      # Creates a new LLM client for the specified provider.
      #
      # This is a convenience method that creates a new Client instance with the
      # given provider and options. It's equivalent to calling
      # `Durable::Llm::Client.new(provider, options)`.
      #
      # @param provider [Symbol, String] The provider name (e.g., :openai, :anthropic)
      # @param options [Hash] Configuration options for the client
      # @option options [String] :model The default model to use
      # @option options [String] :api_key API key for authentication
      # @return [Client] A new client instance
      # @raise [NameError] If the provider is not found
      # @example Create an OpenAI client
      #   client = Durable::Llm.new(:openai, api_key: 'sk-...', model: 'gpt-4')
      # @example Create an Anthropic client
      #   client = Durable::Llm.new(:anthropic, api_key: 'sk-ant-...')
      def new(provider, options = {})
        Client.new(provider, options)
      end
    end

    # Configures the global LLM settings.
    #
    # This method initializes or yields the global configuration instance,
    # allowing you to set API keys, default providers, and other global options.
    #
    # @yield [configuration] The configuration instance to modify
    # @yieldparam configuration [Configuration] The global configuration object
    # @return [void]
    # @example Configure API keys
    #   Durable::Llm.configure do |config|
    #     config.openai.api_key = 'sk-...'
    #     config.anthropic.api_key = 'sk-ant-...'
    #     config.default_provider = 'openai'
    #   end
    # @example Configure from environment
    #   # Environment variables are automatically loaded
    #   ENV['DLLM__OPENAI__API_KEY'] = 'sk-...'
    #   Durable::Llm.configure do |config|
    #     # Additional programmatic configuration
    #   end
    def self.configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    # Creates a quick completion with minimal setup.
    #
    # This is a convenience method for one-off completions that automatically
    # creates a client, performs the completion, and returns the text result.
    #
    # @param text [String] The input text to complete
    # @param provider [Symbol] The provider to use (default: :openai)
    # @param model [String] The model to use (required)
    # @param options [Hash] Additional options for the client
    # @return [String] The completion text
    # @raise [ArgumentError] If required parameters are missing
    # @example Quick completion with OpenAI
    #   result = Durable::Llm.complete('What is Ruby?', model: 'gpt-4')
    #   puts result
    # @example Quick completion with Anthropic
    #   result = Durable::Llm.complete('Explain AI', provider: :anthropic, model: 'claude-3-opus-20240229')
    #   puts result
    def self.complete(text, provider: :openai, model: nil, **options)
      raise ArgumentError, 'text is required' if text.nil? || text.to_s.strip.empty?
      raise ArgumentError, 'model is required' if model.nil? || model.to_s.strip.empty?

      client = new(provider, options.merge(model: model))
      client.complete(text)
    end

    # Creates a chat completion with minimal setup.
    #
    # This is a convenience method for quick chat interactions that automatically
    # creates a client and performs the chat completion.
    #
    # @param messages [Array<Hash>] Array of message hashes with :role and :content
    # @param provider [Symbol] The provider to use (default: :openai)
    # @param model [String] The model to use (required)
    # @param options [Hash] Additional options for the client and request
    # @return [Object] The chat response object
    # @raise [ArgumentError] If required parameters are missing
    # @example Simple chat
    #   response = Durable::Llm.chat(
    #     [{ role: 'user', content: 'Hello!' }],
    #     model: 'gpt-4'
    #   )
    #   puts response.choices.first.message.content
    def self.chat(messages, provider: :openai, model: nil, **options)
      raise ArgumentError, 'messages are required' if messages.nil? || messages.empty?
      raise ArgumentError, 'model is required' if model.nil? || model.to_s.strip.empty?

      request_keys = %i[temperature max_tokens top_p frequency_penalty presence_penalty]
      request_params = options.select { |k, _| request_keys.include?(k) }
      client_options = options.reject { |k, _| request_keys.include?(k) }

      client = new(provider, client_options.merge(model: model))
      client.chat(messages: messages, **request_params)
    end

    # Lists available models for a provider.
    #
    # @param provider [Symbol] The provider name (default: :openai)
    # @param options [Hash] Provider options (e.g., api_key)
    # @return [Array<String>] List of available model IDs
    # @example List OpenAI models
    #   models = Durable::Llm.models(:openai)
    #   puts models.inspect
    def self.models(provider = :openai, **options)
      client = new(provider, options)
      client.provider.models
    end
  end
end

Durable::Llm.configure do
end

require 'durable/llm/providers'
require 'durable/llm/client'
require 'durable/llm/response_helpers'
require 'durable/llm/provider_utilities'

# Load global convenience functions for easier access
# Users can skip this by requiring 'durable/llm/core' instead of 'durable/llm'
require 'durable/llm/convenience' unless ENV['DLLM_NO_CONVENIENCE']

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
