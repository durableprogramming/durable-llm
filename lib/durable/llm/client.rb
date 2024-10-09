require 'zeitwerk'
require 'durable/llm/providers'

module Durable
  module Llm
    class Client
      attr_reader :provider

      def initialize(provider_name, options = {})
        provider_class = Durable::Llm::Providers.const_get(provider_name.to_s.capitalize)

        @provider = provider_class.new(**options)
      end

      def completion(params = {})
        @provider.completion(params)
      end

      def chat(params = {})
        @provider.chat(params)
      end

      def embed(params = {})
        @provider.embed(params)
      end

      def stream(params = {}, &block)
        @provider.stream(params, &block)
      end
    end
  end
end
