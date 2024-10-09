require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, ".rb")
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.push_dir(File.dirname(__FILE__) + '/..' )

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

