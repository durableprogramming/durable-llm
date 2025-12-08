# frozen_string_literal: true

# This module provides helper methods for extracting and formatting responses from
# LLM API calls. It offers convenient methods to work with response objects from
# different providers, abstracting away the complexity of response structure variations.

module Durable
  module Llm
    # Helper methods for working with LLM responses
    #
    # This module provides convenience methods for extracting content, messages,
    # and metadata from LLM response objects. It handles the common patterns of
    # response processing across different providers.
    #
    # @example Using response helpers
    #   response = client.chat(messages: [...])
    #   content = ResponseHelpers.extract_content(response)
    #   tokens = ResponseHelpers.token_usage(response)
    module ResponseHelpers
      module_function

      # Extracts the text content from a completion response
      #
      # @param response [Object] The API response object
      # @return [String, nil] The extracted content or nil if not found
      # @example Extract content from response
      #   response = client.completion(messages: [...])
      #   text = ResponseHelpers.extract_content(response)
      #   puts text
      def extract_content(response)
        return nil unless response
        return nil unless response.respond_to?(:choices)
        return nil if response.choices.empty?

        choice = response.choices.first
        return nil unless choice.respond_to?(:message)

        message = choice.message
        return nil unless message.respond_to?(:content)

        message.content
      end

      # Extracts all choice contents from a response
      #
      # @param response [Object] The API response object
      # @return [Array<String>] Array of content strings from all choices
      # @example Get all alternatives
      #   response = client.completion(messages: [...], n: 3)
      #   alternatives = ResponseHelpers.all_contents(response)
      def all_contents(response)
        return [] unless response&.respond_to?(:choices)

        response.choices.map do |choice|
          next unless choice.respond_to?(:message)

          message = choice.message
          message.content if message.respond_to?(:content)
        end.compact
      end

      # Extracts token usage information from a response
      #
      # @param response [Object] The API response object
      # @return [Hash, nil] Hash with :prompt_tokens, :completion_tokens, :total_tokens
      # @example Get token usage
      #   response = client.completion(messages: [...])
      #   usage = ResponseHelpers.token_usage(response)
      #   puts "Used #{usage[:total_tokens]} tokens"
      def token_usage(response)
        return nil unless response&.respond_to?(:usage)

        usage = response.usage
        return nil unless usage

        {
          prompt_tokens: usage.prompt_tokens,
          completion_tokens: usage.completion_tokens,
          total_tokens: usage.total_tokens
        }
      end

      # Extracts the finish reason from a response
      #
      # @param response [Object] The API response object
      # @return [String, nil] The finish reason (e.g., 'stop', 'length', 'content_filter')
      # @example Check why completion finished
      #   response = client.completion(messages: [...])
      #   reason = ResponseHelpers.finish_reason(response)
      #   puts "Finished because: #{reason}"
      def finish_reason(response)
        return nil unless response&.respond_to?(:choices)
        return nil if response.choices.empty?

        choice = response.choices.first
        choice.finish_reason if choice.respond_to?(:finish_reason)
      end

      # Checks if a response was truncated due to length
      #
      # @param response [Object] The API response object
      # @return [Boolean] True if response was truncated
      # @example Check if truncated
      #   response = client.completion(messages: [...])
      #   if ResponseHelpers.truncated?(response)
      #     puts "Response was cut off. Consider increasing max_tokens."
      #   end
      def truncated?(response)
        finish_reason(response) == 'length'
      end

      # Formats a response as a simple hash with common fields
      #
      # @param response [Object] The API response object
      # @return [Hash] Simplified response hash
      # @example Format response
      #   response = client.completion(messages: [...])
      #   simple = ResponseHelpers.to_hash(response)
      #   # => { content: "...", tokens: {...}, finish_reason: "stop" }
      def to_hash(response)
        {
          content: extract_content(response),
          tokens: token_usage(response),
          finish_reason: finish_reason(response),
          all_contents: all_contents(response)
        }
      end

      # Extracts model information from response
      #
      # @param response [Object] The API response object
      # @return [String, nil] The model used for the completion
      # @example Get model name
      #   response = client.completion(messages: [...])
      #   model = ResponseHelpers.model_used(response)
      #   puts "Model: #{model}"
      def model_used(response)
        return nil unless response&.respond_to?(:model)

        response.model
      end

      # Calculates the cost of a response (approximate)
      #
      # This is a rough estimate based on common pricing. For accurate costs,
      # consult your provider's pricing page.
      #
      # @param response [Object] The API response object
      # @param model [String, nil] Optional model name for pricing lookup
      # @return [Float, nil] Estimated cost in USD
      # @example Estimate cost
      #   response = client.completion(messages: [...])
      #   cost = ResponseHelpers.estimate_cost(response)
      #   puts "Estimated cost: $#{cost}"
      def estimate_cost(response, model = nil)
        usage = token_usage(response)
        return nil unless usage

        model ||= model_used(response)
        return nil unless model

        # Rough pricing estimates (as of 2025)
        pricing = case model
                  when /gpt-4-turbo/
                    { prompt: 0.01 / 1000, completion: 0.03 / 1000 }
                  when /gpt-4/
                    { prompt: 0.03 / 1000, completion: 0.06 / 1000 }
                  when /gpt-3.5-turbo/
                    { prompt: 0.0015 / 1000, completion: 0.002 / 1000 }
                  when /claude-3-opus/
                    { prompt: 0.015 / 1000, completion: 0.075 / 1000 }
                  when /claude-3-sonnet/
                    { prompt: 0.003 / 1000, completion: 0.015 / 1000 }
                  else
                    return nil # Unknown model
                  end

        (usage[:prompt_tokens] * pricing[:prompt]) +
          (usage[:completion_tokens] * pricing[:completion])
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
