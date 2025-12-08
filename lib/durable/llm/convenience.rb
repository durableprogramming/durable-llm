# frozen_string_literal: true

# This file provides global convenience functions for quick access to Durable LLM functionality
# without requiring explicit module qualification. These functions follow Ruby conventions for
# global helper methods and make the library more approachable for quick usage and scripting.
# The functions delegate to the main Durable::Llm module methods while providing shorter names.

# Creates a new Durable LLM client with the specified provider and options.
#
# This is a global convenience function that provides quick access to client creation
# without requiring the full Durable::Llm module path. It's equivalent to calling
# Durable::Llm.new(provider, options).
#
# @param provider [Symbol, String] The provider name (e.g., :openai, :anthropic)
# @param options [Hash] Configuration options for the client
# @option options [String] :model The default model to use
# @option options [String] :api_key API key for authentication
# @return [Durable::Llm::Client] A new client instance
# @example Create an OpenAI client
#   client = DurableLlm(:openai, model: 'gpt-4', api_key: 'sk-...')
#   response = client.complete('Hello!')
# @example Create an Anthropic client
#   client = DurableLlm(:anthropic, model: 'claude-3-opus-20240229')
def DurableLlm(provider, **options)
  Durable::Llm.new(provider, options)
end

# Shorter alias for DurableLlm
#
# @param provider [Symbol, String] The provider name
# @param options [Hash] Configuration options
# @return [Durable::Llm::Client] A new client instance
# @see DurableLlm
def DLLM(provider, **options)
  Durable::Llm.new(provider, options)
end

# Performs a quick text completion with minimal setup
#
# This global convenience function allows for one-line LLM completions without
# explicit client creation. Perfect for scripts and REPL usage.
#
# @param text [String] The input text to complete
# @param provider [Symbol] The provider to use (default: :openai)
# @param model [String] The model to use (required)
# @param options [Hash] Additional client options
# @return [String] The completion text
# @example Quick completion
#   result = LlmComplete('What is Ruby?', model: 'gpt-4')
#   puts result
# @example With specific provider
#   result = LlmComplete('Explain AI', provider: :anthropic, model: 'claude-3-opus-20240229')
def LlmComplete(text, provider: :openai, model: nil, **options)
  Durable::Llm.complete(text, provider: provider, model: model, **options)
end

# Performs a chat completion with minimal setup
#
# This global convenience function allows for quick chat interactions without
# explicit client creation.
#
# @param messages [Array<Hash>] Array of message hashes with :role and :content
# @param provider [Symbol] The provider to use (default: :openai)
# @param model [String] The model to use (required)
# @param options [Hash] Additional options
# @return [Object] The chat response object
# @example Simple chat
#   response = LlmChat([{ role: 'user', content: 'Hello!' }], model: 'gpt-4')
#   puts response.choices.first.message.content
def LlmChat(messages, provider: :openai, model: nil, **options)
  Durable::Llm.chat(messages, provider: provider, model: model, **options)
end

# Lists available models for a provider
#
# @param provider [Symbol] The provider name (default: :openai)
# @param options [Hash] Provider options
# @return [Array<String>] List of available model IDs
# @example List models
#   models = LlmModels(:openai)
#   puts models.inspect
def LlmModels(provider = :openai, **options)
  Durable::Llm.models(provider, **options)
end

# Configures Durable LLM with a block
#
# This global convenience function provides easy access to configuration.
#
# @yield [configuration] The configuration instance to modify
# @yieldparam configuration [Durable::Llm::Configuration] The config object
# @return [void]
# @example Configure API keys
#   LlmConfigure do |config|
#     config.openai.api_key = 'sk-...'
#     config.anthropic.api_key = 'sk-ant-...'
#   end
def LlmConfigure(&block)
  Durable::Llm.configure(&block)
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
