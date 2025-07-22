# frozen_string_literal: true

# This file serves as the main entry point for the Durable::Llm module, providing namespace organization and configuration management for LLM providers. It uses Zeitwerk for autoloading, sets up the module structure with configuration support, and initializes an empty default configuration block that can be customized by users to set API keys and provider settings.

require 'zeitwerk'
loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, '.rb')
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.push_dir("#{File.dirname(__FILE__)}/..")

require 'durable/llm/configuration'

module Durable
  module Llm
    class << self
      attr_accessor :configuration

      def config
        configuration
      end
    end

    def self.configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end
  end
end

Durable::Llm.configure do
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
