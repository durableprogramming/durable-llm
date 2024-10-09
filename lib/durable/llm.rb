require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.setup

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
