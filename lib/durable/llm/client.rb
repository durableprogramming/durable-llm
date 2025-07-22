# This file implements the main Client class that provides a unified interface for interacting with different LLM providers. It acts as a facade that delegates operations like completion, chat, embedding, and streaming to the appropriate provider instance while handling parameter processing, model configuration, and providing convenience methods for quick text completion. The client automatically resolves provider classes based on the provider name and manages default parameters including model selection.

require 'zeitwerk'
require 'durable/llm/providers'

module Durable
  module Llm
    class Client
      attr_reader :provider
      attr_accessor :model

      def initialize(provider_name, options = {})
        @model = options.delete('model') || options.delete(:model) if options['model'] || options[:model]

        provider_class = Durable::Llm::Providers.const_get(provider_name.to_s.capitalize)

        @provider = provider_class.new(**options)
      end

      def default_params
        { model: @model }
      end

      def quick_complete(text, _opts = {})
        response = completion(process_params(messages: [{ role: 'user', content: text }]))

        response.choices.first.message.content
      end

      def completion(params = {})
        @provider.completion(process_params(params))
      end

      def chat(params = {})
        @provider.chat(process_params(params))
      end

      def embed(params = {})
        @provider.embed(process_params(params))
      end

      def stream(params = {}, &block)
        @provider.stream(process_params(params), &block)
      end

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