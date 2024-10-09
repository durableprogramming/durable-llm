module Durable
  module Llm
    module Providers
      class Base
        def default_api_key
          raise NotImplementedError, "Subclasses must implement default_api_key"
        end

        attr_accessor :api_key

        def initialize(api_key: nil)
          @api_key = api_key || default_api_key
        end


        def completion(options)
          raise NotImplementedError, "Subclasses must implement completion"
        end

        def self.models 
          []
        end
        def models
          raise NotImplementedError, "Subclasses must implement models"
        end

        def self.stream?
          false
        end
        def stream?
          self.class.stream?
        end

        def stream(options, &block)
          raise NotImplementedError, "Subclasses must implement stream"
        end

        def embedding(model:, input:, **options)
          raise NotImplementedError, "Subclasses must implement embedding"
        end

        private

        def handle_response(response)
          raise NotImplementedError, "Subclasses must implement handle_response"
        end
      end
    end
  end
end
