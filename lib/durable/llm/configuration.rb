# frozen_string_literal: true

# frozen_string_literal: true

require 'ostruct'

module Durable
  module Llm
    # Configuration class for managing LLM provider settings and API keys.
    #
    # This class provides a centralized configuration management system for the Durable LLM gem.
    # It supports dynamic provider configuration through method_missing, automatic loading from
    # environment variables using the `DLLM__` prefix pattern, and optional integration with
    # Datasette LLM configuration files.
    #
    # ## Basic Usage
    #
    # ```ruby
    # config = Durable::Llm::Configuration.new
    #
    # # Configure providers dynamically
    # config.openai = { api_key: 'sk-...', model: 'gpt-4' }
    # config.anthropic.api_key = 'sk-ant-...'
    #
    # # Set default provider
    # config.default_provider = 'anthropic'
    # ```
    #
    # ## Environment Variable Configuration
    #
    # Configuration can be loaded from environment variables using the `DLLM__` prefix:
    #
    # ```bash
    # export DLLM__OPENAI__API_KEY=sk-your-key
    # export DLLM__ANTHROPIC__API_KEY=sk-ant-your-key
    # export DLLM__OPENAI__MODEL=gpt-4
    # ```
    #
    # ## Datasette LLM Integration
    #
    # The configuration automatically loads API keys from Datasette LLM's configuration file
    # at `~/.config/io.datasette.llm/keys.json` when `load_from_datasette` is called.
    #
    # @example Dynamic provider configuration
    #   config = Durable::Llm::Configuration.new
    #   config.openai.api_key = 'sk-...'
    #   config.anthropic = { api_key: 'sk-ant-...', model: 'claude-3' }
    #
    # @example Environment variable loading
    #   ENV['DLLM__OPENAI__API_KEY'] = 'sk-...'
    #   config = Durable::Llm::Configuration.new # Automatically loads from env
    #
    # @example Datasette integration
    #   config.load_from_datasette # Loads from ~/.config/io.datasette.llm/keys.json
    #
    # @see Durable::Llm::Client
    # @see Durable::Llm::Providers
    class Configuration
      # @return [String] The default provider name to use when none is specified
      attr_accessor :default_provider

      # @return [Hash<Symbol, OpenStruct>] Hash of provider configurations keyed by provider name
      attr_reader :providers

      # Initializes a new Configuration instance.
      #
      # Creates an empty providers hash, sets the default provider to 'openai',
      # and automatically loads configuration from environment variables.
      #
      # @return [Configuration] A new configuration instance
      def initialize
        @providers = {}
        @default_provider = 'openai'
        load_from_env
      end

      # Clears all provider configurations and resets to defaults.
      #
      # This method removes all configured providers, resets the default provider
      # to 'openai', and reloads configuration from environment variables.
      #
      # @return [void]
      def clear
        @providers.clear
        @default_provider = 'openai'
        load_from_env
      end

      # Loads API keys from Datasette LLM configuration file.
      #
      # This method attempts to load API keys from the Datasette LLM configuration
      # file located at `~/.config/io.datasette.llm/keys.json`. If the file exists
      # and contains valid JSON, it will populate the API keys for any configured
      # providers that have matching entries in the file.
      #
      # The method gracefully handles missing files, invalid JSON, and other
      # file system errors by issuing warnings and continuing execution.
      #
      # @return [void]
      # @example Load Datasette configuration
      #   config = Durable::Llm::Configuration.new
      #   config.load_from_datasette # Loads keys from ~/.config/io.datasette.llm/keys.json
      def load_from_datasette
        config_file = File.expand_path('~/.config/io.datasette.llm/keys.json')

        return unless File.exist?(config_file)

        begin
          config_data = JSON.parse(File.read(config_file))

          Durable::Llm::Providers.providers.each do |provider|
            next unless config_data[provider.to_s]

            @providers[provider.to_sym] ||= OpenStruct.new
            @providers[provider.to_sym].api_key = config_data[provider.to_s]
          end
        rescue JSON::ParserError => e
          warn "Error parsing Datasette LLM configuration file: #{e.message}"
        rescue StandardError => e
          warn "Error loading Datasette LLM configuration: #{e.message}"
        end
      end

      # Loads configuration from environment variables.
      #
      # This method scans all environment variables for those starting with the
      # `DLLM__` prefix and automatically configures provider settings based on
      # the variable names. The format is `DLLM__PROVIDER__SETTING=value`.
      #
      # For example:
      # - `DLLM__OPENAI__API_KEY=sk-...` sets the API key for OpenAI
      # - `DLLM__ANTHROPIC__MODEL=claude-3` sets the default model for Anthropic
      #
      # Provider and setting names are converted to lowercase symbols for consistency.
      #
      # @return [void]
      # @example Environment variable configuration
      #   ENV['DLLM__OPENAI__API_KEY'] = 'sk-...'
      #   ENV['DLLM__ANTHROPIC__MODEL'] = 'claude-3'
      #   config = Durable::Llm::Configuration.new # Automatically loads these values
      def load_from_env
        ENV.each do |key, value|
          next unless key.start_with?('DLLM__')

          parts = key.split('__')
          next unless parts.length >= 3 # Must have DLLM__PROVIDER__SETTING

          provider = parts[1].downcase.to_sym
          setting = parts[2].downcase.to_sym
          @providers[provider] ||= OpenStruct.new
          @providers[provider][setting] = value
        end
      end

      # Provides dynamic access to provider configurations.
      #
      # This method implements dynamic method dispatch for provider configuration.
      # It allows accessing and setting provider configurations using method calls
      # like `config.openai` or `config.openai = { api_key: '...' }`.
      #
      # ## Getter Methods
      #
      # When called without an assignment (e.g., `config.openai`), it returns
      # an OpenStruct for the specified provider, creating one if it doesn't exist.
      #
      # ## Setter Methods
      #
      # When called with an assignment (e.g., `config.openai = ...`), it sets
      # the configuration for the provider:
      #
      # - If passed a Hash, merges the hash values into the provider's OpenStruct
      # - If passed any other object, replaces the provider's configuration entirely
      #
      # @param method_name [Symbol] The method name being called
      # @param args [Array] Arguments passed to the method
      # @return [OpenStruct] For getter calls, returns the provider configuration
      # @return [Object] For setter calls, returns the assigned value
      # @example Dynamic getter
      #   config.openai # => #<OpenStruct>
      # @example Hash setter (merges values)
      #   config.openai = { api_key: 'sk-...', model: 'gpt-4' }
      # @example Object setter (replaces configuration)
      #   config.openai = OpenStruct.new(api_key: 'sk-...')
      def method_missing(method_name, *args)
        provider_name = method_name.to_s.chomp('=').to_sym

        if method_name.to_s.end_with?('=')
          @providers[provider_name] ||= OpenStruct.new
          if args.first.is_a?(Hash)
            args.first.each { |k, v| @providers[provider_name][k] = v }
          else
            @providers[provider_name] = args.first
          end
        else
          @providers[provider_name] ||= OpenStruct.new
        end
      end

      # Indicates whether the configuration responds to the given method.
      #
      # This method always returns true to support dynamic provider configuration
      # methods. Any method call on the configuration object is considered valid
      # since providers are created dynamically as needed.
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] Always returns true
      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
