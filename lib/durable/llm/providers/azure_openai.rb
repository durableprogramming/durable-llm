# frozen_string_literal: true

# Azure OpenAI provider implementation for Durable LLM

require 'faraday'
require 'json'
require 'durable/llm/errors'
require 'durable/llm/providers/base'
require 'event_stream_parser'

module Durable
  module Llm
    module Providers
      # Azure OpenAI provider for accessing Azure OpenAI's language models
      #
      # This provider implements the Azure OpenAI API for chat completions,
      # embeddings, and streaming. It handles authentication via API keys,
      # deployment-based routing, and response normalization.
      class AzureOpenai < Durable::Llm::Providers::Base
        BASE_URL_TEMPLATE = 'https://%s.openai.azure.com/openai/deployments/%s'

        def default_api_key
          begin
            Durable::Llm.configuration.azure_openai&.api_key
          rescue NoMethodError
            nil
          end || ENV['AZURE_OPENAI_API_KEY']
        end

        attr_accessor :api_key, :resource_name, :api_version

        def initialize(api_key: nil, resource_name: nil, api_version: '2024-02-01')
          super(api_key: api_key)
          @resource_name = resource_name || ENV['AZURE_OPENAI_RESOURCE_NAME']
          @api_version = api_version
          # NOTE: BASE_URL will be constructed per request since deployment is in model
        end

        def completion(options)
          model = options.delete(:model) || options.delete('model')
          base_url = format(BASE_URL_TEMPLATE, @resource_name, model)
          conn = build_connection(base_url)

          response = conn.post('chat/completions') do |req|
            req.headers['api-key'] = @api_key
            req.params['api-version'] = @api_version
            req.body = options
          end

          handle_response(response)
        end

        def embedding(model:, input:, **options)
          base_url = format(BASE_URL_TEMPLATE, @resource_name, model)
          conn = build_connection(base_url)

          response = conn.post('embeddings') do |req|
            req.headers['api-key'] = @api_key
            req.params['api-version'] = @api_version
            req.body = { input: input, **options }
          end

          handle_response(response, AzureOpenaiEmbeddingResponse)
        end

        def models
          # Azure OpenAI doesn't have a public models endpoint, return hardcoded list
          [
            # GPT-5 series
            'gpt-5',
            'gpt-5-mini',
            'gpt-5-nano',
            'gpt-5-chat',
            'gpt-5-codex',
            'gpt-5-pro',
            # GPT-4.1 series
            'gpt-4.1',
            'gpt-4.1-mini',
            'gpt-4.1-nano',
            # GPT-4o series
            'gpt-4o',
            'gpt-4o-mini',
            'gpt-4o-audio-preview',
            'gpt-4o-mini-audio-preview',
            'gpt-4o-realtime-preview',
            'gpt-4o-mini-realtime-preview',
            'gpt-4o-transcribe',
            'gpt-4o-mini-transcribe',
            'gpt-4o-mini-tts',
            # GPT-4 Turbo
            'gpt-4-turbo',
            # GPT-4
            'gpt-4',
            'gpt-4-32k',
            # GPT-3.5
            'gpt-3.5-turbo',
            'gpt-35-turbo',
            'gpt-35-turbo-instruct',
            # O-series
            'o3',
            'o3-mini',
            'o3-pro',
            'o4-mini',
            'o1',
            'o1-mini',
            'o1-preview',
            'codex-mini',
            # Embeddings
            'text-embedding-ada-002',
            'text-embedding-3-small',
            'text-embedding-3-large',
            # Audio
            'whisper',
            'gpt-4o-transcribe',
            'gpt-4o-mini-transcribe',
            'tts',
            'tts-hd',
            'gpt-4o-mini-tts',
            # Image generation
            'dall-e-3',
            'gpt-image-1',
            'gpt-image-1-mini',
            # Video generation
            'sora',
            # Other
            'model-router',
            'computer-use-preview',
            'gpt-oss-120b',
            'gpt-oss-20b'
          ]
        end

        def self.stream?
          true
        end

        def stream(options)
          model = options[:model] || options['model']
          base_url = format(BASE_URL_TEMPLATE, @resource_name, model)
          conn = build_connection(base_url)

          options[:stream] = true
          options['temperature'] = options['temperature'].to_f if options['temperature']

          response = conn.post('chat/completions') do |req|
            setup_stream_request(req, options) do |chunk|
              yield AzureOpenaiStreamResponse.new(chunk)
            end
          end

          handle_response(response)
        end

        def setup_stream_request(req, options)
          req.headers['api-key'] = @api_key
          req.params['api-version'] = @api_version
          req.headers['Accept'] = 'text/event-stream'
          req.body = options

          user_proc = proc do |chunk, _size, _total|
            yield chunk
          end

          req.options.on_data = to_json_stream(user_proc: user_proc)
        end

        private

        def build_connection(base_url)
          Faraday.new(url: base_url) do |faraday|
            faraday.request :json
            faraday.response :json
            faraday.adapter Faraday.default_adapter
          end
        end

        # CODE-FROM: ruby-openai @ https://github.com/alexrudall/ruby-openai/blob/main/lib/openai/http.rb
        # MIT License: https://github.com/alexrudall/ruby-openai/blob/main/LICENSE.md
        def to_json_stream(user_proc:)
          parser = EventStreamParser::Parser.new

          proc do |chunk, _bytes, env|
            if env && env.status != 200
              raise_error = Faraday::Response::RaiseError.new
              raise_error.on_complete(env.merge(body: try_parse_json(chunk)))
            end

            parser.feed(chunk) do |_type, data|
              user_proc.call(JSON.parse(data)) unless data == '[DONE]'
            end
          end
        end

        def try_parse_json(maybe_json)
          JSON.parse(maybe_json)
        rescue JSON::ParserError
          maybe_json
        end

        # END-CODE-FROM

        def handle_response(response, response_class = AzureOpenaiResponse)
          case response.status
          when 200..299
            response_class.new(response.body)
          else
            raise_error(response)
          end
        end

        def raise_error(response)
          error_class = case response.status
                        when 401 then Durable::Llm::AuthenticationError
                        when 429 then Durable::Llm::RateLimitError
                        when 400..499 then Durable::Llm::InvalidRequestError
                        when 500..599 then Durable::Llm::ServerError
                        else Durable::Llm::APIError
                        end

          message = if error_class == Durable::Llm::APIError
                      "Unexpected response code: #{response.status}"
                    else
                      parse_error_message(response)
                    end

          raise error_class, message
        end

        def parse_error_message(response)
          body = begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          message = body&.dig('error', 'message') || response.body
          "#{response.status} Error: #{message}"
        end

        # Response wrapper for Azure OpenAI completion API responses
        class AzureOpenaiResponse
          attr_reader :raw_response

          def initialize(response)
            @raw_response = response
          end

          def choices
            @raw_response['choices'].map { |choice| AzureOpenaiChoice.new(choice) }
          end

          def data
            @raw_response['data']
          end

          def to_s
            choices.map(&:to_s).join(' ')
          end
        end

        # Choice wrapper for Azure OpenAI API responses
        class AzureOpenaiChoice
          attr_reader :message, :finish_reason

          def initialize(choice)
            @message = AzureOpenaiMessage.new(choice['message'])
            @finish_reason = choice['finish_reason']
          end

          def to_s
            @message.to_s
          end
        end

        # Message wrapper for Azure OpenAI API responses
        class AzureOpenaiMessage
          attr_reader :role, :content

          def initialize(message)
            @role = message['role']
            @content = message['content']
          end

          def to_s
            @content
          end
        end

        # Stream response wrapper for Azure OpenAI streaming API
        class AzureOpenaiStreamResponse
          attr_reader :choices

          def initialize(parsed)
            @choices = AzureOpenaiStreamChoice.new(parsed['choices'])
          end

          def to_s
            @choices.to_s
          end
        end

        # Embedding response wrapper for Azure OpenAI embedding API
        class AzureOpenaiEmbeddingResponse
          attr_reader :embedding

          def initialize(data)
            @embedding = data.dig('data', 0, 'embedding')
          end

          def to_a
            @embedding
          end
        end

        # Stream choice wrapper for Azure OpenAI streaming responses
        class AzureOpenaiStreamChoice
          attr_reader :delta, :finish_reason

          def initialize(choice)
            @choice = [choice].flatten.first
            @delta = AzureOpenaiStreamDelta.new(@choice['delta'])
            @finish_reason = @choice['finish_reason']
          end

          def to_s
            @delta.to_s
          end
        end

        # Stream delta wrapper for Azure OpenAI streaming responses
        class AzureOpenaiStreamDelta
          attr_reader :role, :content

          def initialize(delta)
            @role = delta['role']
            @content = delta['content']
          end

          def to_s
            @content || ''
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
