require 'ostruct'

module Durable
  module Llm
    class Configuration
      attr_accessor :default_provider
      attr_reader :providers

      def initialize
        @providers = {}
        @default_provider = 'openai'
        load_from_env
      end

      def clear
        @providers.clear
        @default_provider = 'openai'
      end

      def load_from_datasette
        config_file = File.expand_path('~/.config/io.datasette.llm/keys.json')

        if File.exist?(config_file)
          config_data = JSON.parse(File.read(config_file))

          Durable::Llm::Providers.providers.each do |provider|
            @providers[provider.to_sym] ||= OpenStruct.new

            @providers[provider.to_sym][:api_key] = config_data[provider.to_s] if config_data[provider.to_s]
          end
        end
      rescue JSON::ParserError => e
        puts "Error parsing JSON file: #{e.message}"
      end

      def load_from_env
        ENV.each do |key, value|
          next unless key.start_with?('DLLM__')

          parts = key.split('__')
          provider = parts[1].downcase.to_sym
          setting = parts[2].downcase.to_sym
          @providers[provider] ||= OpenStruct.new
          @providers[provider][setting] = value
        end
      end

      def method_missing(method_name, *args)
        if method_name.to_s.end_with?('=')
          provider = method_name.to_s.chomp('=').to_sym
          @providers[provider] = args.first
        else
          @providers[method_name]
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.end_with?('=') || @providers.key?(method_name) || super
      end
    end
  end
end
