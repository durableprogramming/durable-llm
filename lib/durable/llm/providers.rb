require 'durable/llm/providers/openai'
require 'durable/llm/providers/anthropic'

module Durable
  module Llm
    module Providers
      def self.load_all
        Dir[File.join(__dir__, 'providers', '*.rb')].each { |file| require file }
      end

      def self.providers
        @provider_list ||= constants.select do |const_name|
          const = const_get(const_name)
          last_component = const.name.split('::').last
          next if last_component == 'Base'

          const.is_a?(Class) && const.to_s.split('::').last.to_s == const_name.to_s
        end.map(&:to_s).map(&:downcase).map(&:to_sym)
      end

      def self.model_ids
        providers.flat_map do |provider|
          provider_class = const_get(provider.to_s.capitalize)
          provider_class.models
        end
      end

      def self.model_id_to_provider(model_id)
        providers.each do |provider|
          provider_class = const_get(provider.to_s.capitalize)
          return provider_class if provider_class.models.include?(model_id)
        end
        nil
      end

      Openai = OpenAI
      Claude = Anthropic
      Claude3 = Anthropic
    end
  end
end
