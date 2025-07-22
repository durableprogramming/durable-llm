# frozen_string_literal: true

# This file defines the abstract base class for all LLM providers in the Durable gem, establishing a common interface and shared functionality that all provider implementations must follow. It defines required methods like completion, models, and streaming capabilities, provides caching mechanisms for model lists, handles default API key resolution, and includes stub implementations for optional features like embeddings. The base class ensures consistency across different LLM providers while allowing each provider to implement their specific API communication patterns and response handling.

module Durable
  module Llm
    module Providers
      class Base
        def default_api_key
          raise NotImplementedError, 'Subclasses must implement default_api_key'
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
        end

        def completion(options)
          raise NotImplementedError, 'Subclasses must implement completion'
        end

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

        def models
          raise NotImplementedError, 'Subclasses must implement models'
        end

        def self.stream?
          false
        end

        def stream?
          self.class.stream?
        end

        def stream(options, &block)
          raise NotImplementedError, 'Subclasses must implement stream'
        end

        def embedding(model:, input:, **options)
          raise NotImplementedError, 'Subclasses must implement embedding'
        end

        private

        def handle_response(response)
          raise NotImplementedError, 'Subclasses must implement handle_response'
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
