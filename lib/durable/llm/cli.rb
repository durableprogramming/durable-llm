# This file implements the command-line interface for the Durable LLM gem using Thor, providing commands for single prompts, interactive chat sessions, and listing available models. It handles provider resolution, streaming responses, model options, system prompts, and conversation management through a user-friendly CLI with support for both one-shot completions and multi-turn conversations.

require 'thor'
require 'durable/llm'
require 'durable/llm/client'
require 'highline'

module Durable
  module Llm
    class CLI < Thor
      def self.exit_on_failure?
        true
      end

      desc 'prompt PROMPT', 'Run a prompt'
      option :model, aliases: '-m', desc: 'Specify the model to use'
      option :system, aliases: '-s', desc: 'Set a system prompt'
      option :continue, aliases: '-c', type: :boolean, desc: 'Continue the previous conversation'
      option :conversation, aliases: '--cid', desc: 'Continue a specific conversation by ID'
      option :no_stream, type: :boolean, desc: 'Disable streaming of tokens'
      option :option, aliases: '-o', type: :hash, desc: 'Set model-specific options'

      def prompt(*prompt)
        model = options[:model] || 'gpt-3.5-turbo'
        provider_class = Durable::Llm::Providers.model_id_to_provider(model)

        raise "no provider found for model '#{model}'" if provider_class.nil?

        provider_name = provider_class.name.split('::').last.downcase.to_sym
        client = Durable::Llm::Client.new(provider_name)

        messages = []
        messages << { role: 'system', content: options[:system] } if options[:system]
        messages << { role: 'user', content: prompt.join(' ') }

        params = {
          model: model,
          messages: messages
        }
        params.merge!(options[:option]) if options[:option]

        if options[:no_stream] || !client.stream?
          response = client.completion(params)
          puts response.choices.first
        else
          client.stream(params) do |chunk|
            print chunk
            $stdout.flush
          end
        end
      end

      desc 'chat', 'Start an interactive chat'
      option :model, aliases: '-m', desc: 'Specify the model to use'
      option :system, aliases: '-s', desc: 'Set a system prompt'
      option :continue, aliases: '-c', type: :boolean, desc: 'Continue the previous conversation'
      option :conversation, aliases: '--cid', desc: 'Continue a specific conversation by ID'
      option :option, aliases: '-o', type: :hash, desc: 'Set model-specific options'
      def chat
        model = options[:model] || 'gpt-3.5-turbo'
        provider_class = Durable::Llm::Providers.model_id_to_provider(model)

        raise "no provider found for model '#{model}'" if provider_class.nil? || provider_class.name.nil?

        provider_name = provider_class.name.split('::').last.downcase.to_sym
        client = Durable::Llm::Client.new(provider_name)

        messages = []
        messages << { role: 'system', content: options[:system] } if options[:system]

        cli = HighLine.new

        cli.say("Chatting with #{model}")
        cli.say("Type 'exit' or 'quit' to exit")
        cli.say("Type '!multi' to enter multiple lines, then '!end' to finish")

        loop do
          input = cli.ask('> ')
          break if %w[exit quit].include?(input.downcase)

          if input == '!multi'
            input = cli.ask("Enter multiple lines. Type '!end' to finish:") do |q|
              q.gather = '!end'
            end
          end

          messages << { role: 'user', content: input }
          params = {
            model: model,
            messages: messages
          }
          params.merge!(options[:option]) if options[:option]

          response = client.completion(params)
          cli.say(response.choices.first.to_s)
          messages << { role: 'assistant', content: response.choices.first.to_s }
        end
      end

      desc 'models', 'List available models'
      option :options, type: :boolean, desc: 'Show model options'
      def models
        cli = HighLine.new
        cli.say('Available models:')

        Durable::Llm::Providers.providers.each do |provider_name|
          provider_class = Durable::Llm::Providers.const_get(provider_name.to_s.capitalize)
          provider_models = provider_class.models

          cli.say("#{provider_name.to_s.capitalize}:")
          provider_models.each do |model|
            cli.say("  #{model}")
          end
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.