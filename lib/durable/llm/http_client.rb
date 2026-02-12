# frozen_string_literal: true

# Faraday-based HTTP client implementation for durable-llm.
# This encapsulates Faraday-specific code to make it easier to swap out
# the HTTP client library in variants (e.g., HTTParty, Net::HTTP).

require 'faraday'
require 'json'
require 'event_stream_parser'
require 'ostruct'

module Durable
  module Llm
    # Faraday-based HTTP client that provides a common interface for HTTP operations
    class HttpClient
      class Response
        attr_reader :status, :body

        def initialize(faraday_response)
          @faraday_response = faraday_response
          @status = faraday_response.status
          @body = faraday_response.body
        end
      end

      def initialize(url:)
        @base_url = url
        @conn = Faraday.new(url: url) do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.adapter Faraday.default_adapter
        end
      end

      def post(path)
        request = Request.new(@conn, path)
        yield request if block_given?

        faraday_response = @conn.post(path) do |req|
          request.headers.each { |k, v| req.headers[k] = v }
          req.body = request.body if request.body
          req.options.on_data = request.options.on_data if request.options.on_data
        end

        Response.new(faraday_response)
      end

      # Performs a POST request with streaming support for Server-Sent Events (SSE).
      #
      # This method handles streaming responses from APIs that use the SSE format,
      # parsing individual JSON events and calling the provided callback with each chunk.
      # It's designed to work with LLM streaming APIs like OpenAI and Anthropic.
      #
      # @param path [String] The API endpoint path (relative to base_url)
      # @yield [stream_request] Yields a StreamRequest object for fluent configuration
      # @yieldparam stream_request [StreamRequest] The stream request object to configure
      # @return [Response] The final HTTP response after streaming completes
      # @raise [NotImplementedError] If the HTTP client doesn't support streaming
      #
      # @example Fluent streaming interface
      #   client.post_stream('chat/completions') do |stream|
      #     stream.on_chunk { |chunk| puts chunk['choices'].first['delta']['content'] }
      #     stream.headers['Authorization'] = 'Bearer token'
      #     stream.body = { model: 'gpt-4', messages: [...], stream: true }
      #   end
      #
      # @note Uses fluent callback style with on_chunk method
      # @note Automatically filters out '[DONE]' sentinel values
      # @note Handles error responses (non-200 status codes) during streaming
      def post_stream(path)
        unless respond_to?(:streaming_supported?) ? streaming_supported? : true
          raise NotImplementedError, 'This HTTP client does not support streaming'
        end

        stream_request = StreamRequest.new(@conn, path)

        # Yield the stream request for configuration
        yield stream_request if block_given?

        parser = EventStreamParser::Parser.new
        stream_handler = stream_request.chunk_handler

        # Create the streaming callback that parses SSE and yields JSON objects
        stream_request.options.on_data = proc do |chunk, _bytes, env|
          if env && env.status != 200
            raise_error = Faraday::Response::RaiseError.new
            raise_error.on_complete(env.merge(body: try_parse_json(chunk)))
          end

          parser.feed(chunk) do |_type, data|
            next if data == '[DONE]'

            begin
              parsed_chunk = JSON.parse(data)
              stream_handler&.call(parsed_chunk)
            rescue JSON::ParserError
              # Skip malformed JSON chunks
            end
          end
        end

        begin
          faraday_response = @conn.post(path) do |req|
            stream_request.headers.each { |k, v| req.headers[k] = v }
            req.body = stream_request.body if stream_request.body
            req.options.on_data = stream_request.options.on_data if stream_request.options.on_data
          end

          Response.new(faraday_response)
        rescue Faraday::UnauthorizedError => e
          # Create a fake response object for consistent error handling
          Response.new(OpenStruct.new(status: 401, body: e.response_body))
        rescue Faraday::TooManyRequestsError => e
          # Create a fake response object for consistent error handling
          Response.new(OpenStruct.new(status: 429, body: e.response_body))
        rescue Faraday::ClientError => e
          # Handle other 4xx errors
          Response.new(OpenStruct.new(status: e.response_status, body: e.response_body))
        rescue Faraday::ServerError => e
          # Handle 5xx errors
          Response.new(OpenStruct.new(status: e.response_status, body: e.response_body))
        end
      end

      # Checks if this HTTP client supports streaming
      #
      # @return [Boolean] true if streaming is supported
      def streaming_supported?
        true
      end

      def get(path)
        request = Request.new(@conn, path)
        yield request if block_given?

        faraday_response = @conn.get(path) do |req|
          request.headers.each { |k, v| req.headers[k] = v }
        end

        Response.new(faraday_response)
      end

      class Request
        attr_accessor :headers, :body, :options

        def initialize(conn, path)
          @conn = conn
          @path = path
          @headers = {}
          @body = nil
          @options = RequestOptions.new(conn)
        end
      end

      # Fluent interface for streaming requests
      class StreamRequest < Request
        attr_reader :chunk_handler

        def initialize(conn, path)
          super
          @chunk_handler = nil
        end

        # Set the callback for processing stream chunks
        # @yield [chunk] Receives each parsed JSON chunk
        # @yieldparam chunk [Hash] The parsed JSON chunk
        # @return [self] Returns self for method chaining
        def on_chunk(&block)
          @chunk_handler = block
          self
        end
      end

      class RequestOptions
        attr_accessor :on_data

        def initialize(conn)
          @conn = conn
          @on_data = nil
        end
      end

      private

      # Attempts to parse a string as JSON, returning the string if parsing fails.
      #
      # This is used to provide better error messages when streaming requests fail,
      # ensuring error responses are parsed if possible but falling back to raw text.
      #
      # @param maybe_json [String] The string that might be JSON
      # @return [Hash, Array, String] The parsed JSON object or the original string
      def try_parse_json(maybe_json)
        JSON.parse(maybe_json)
      rescue JSON::ParserError
        maybe_json
      end
    end
  end
end
