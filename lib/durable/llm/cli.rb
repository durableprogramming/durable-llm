# frozen_string_literal: true

# This file implements the command-line interface for the Durable LLM gem using Thor, providing commands for single prompts, interactive chat sessions, and listing available models. It handles provider resolution, streaming responses, model options, system prompts, and conversation management through a user-friendly CLI with support for both one-shot completions and multi-turn conversations.

require 'thor'
require 'highline'
require 'json'
require 'securerandom'
require 'fileutils'
require 'time'
require 'durable/llm/client'
require 'durable/llm/providers'

module Durable
  module Llm
    # Command-line interface for Durable LLM gem.
    #
    # Provides Thor-based CLI commands for interacting with LLM providers.
    class CLI < Thor
      def self.exit_on_failure?
        true
      end

      CONVERSATIONS_DIR = File.expand_path('~/.durable_llm/conversations')
      LAST_CONVERSATION_FILE = File.join(CONVERSATIONS_DIR, 'last_conversation.txt')

      no_commands do
        def conversation_file_path(id)
          File.join(CONVERSATIONS_DIR, "#{id}.json")
        end

        def load_conversation(id)
          path = conversation_file_path(id)
          return nil unless File.exist?(path)

          JSON.parse(File.read(path))
        end

        def save_conversation(conversation)
          FileUtils.mkdir_p(CONVERSATIONS_DIR) unless Dir.exist?(CONVERSATIONS_DIR)
          id = conversation['id'] || SecureRandom.uuid
          conversation['id'] = id
          conversation['updated_at'] = Time.now.iso8601
          File.write(conversation_file_path(id), JSON.generate(conversation))
          File.write(LAST_CONVERSATION_FILE, id)
          id
        end

        def last_conversation_id
          return nil unless File.exist?(LAST_CONVERSATION_FILE)

          File.read(LAST_CONVERSATION_FILE).strip
        end
      end

      # Run a single prompt and get a response
      #
      # @param prompt [Array<String>] The prompt text to send to the model
      # @option options :model [String] The model to use (default: gpt-3.5-turbo)
      # @option options :system [String] System prompt to set context
      # @option options :continue [Boolean] Continue the last conversation
      # @option options :conversation [String] Continue a specific conversation by ID
      # @option options :no_stream [Boolean] Disable streaming responses
      # @option options :option [Hash] Additional model-specific options
      # @return [void] Outputs the response to stdout
      # @raise [RuntimeError] If no provider is found for the specified model
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

        conversation_id = options[:conversation] || (options[:continue] ? last_conversation_id : nil)
        conversation = conversation_id ? load_conversation(conversation_id) : nil

        messages = conversation ? conversation['messages'].dup : []
        messages << { role: 'system', content: options[:system] } if options[:system] && !conversation
        messages << { role: 'user', content: prompt.join(' ') }

        params = {
          model: model,
          messages: messages
        }
        params.merge!(options[:option]) if options[:option]

        begin
          if options[:no_stream] || !client.stream?
            response = client.completion(**params)
            assistant_message = response.choices.first.to_s
            puts assistant_message
            messages << { role: 'assistant', content: assistant_message }
          else
            assistant_content = ''
            client.stream(**params) do |chunk|
              print chunk
              assistant_content += chunk
              $stdout.flush
            end
            messages << { role: 'assistant', content: assistant_content }
          end

          # Save conversation
          conversation_data = {
            'id' => conversation_id,
            'model' => model,
            'messages' => messages,
            'created_at' => conversation ? conversation['created_at'] : Time.now.iso8601
          }
          save_conversation(conversation_data)
        rescue Durable::Llm::Error => e
          warn "API Error: #{e.message}"
          exit 1
        rescue StandardError => e
          warn "Unexpected error: #{e.message}"
          exit 1
        end
      end

      # Start an interactive chat session with the model
      #
      # @option options :model [String] The model to use (default: gpt-3.5-turbo)
      # @option options :system [String] System prompt to set context
      # @option options :continue [Boolean] Continue the last conversation
      # @option options :conversation [String] Continue a specific conversation by ID
      # @option options :no_stream [Boolean] Disable streaming responses
      # @option options :option [Hash] Additional model-specific options
      # @return [void] Starts interactive chat session
      # @raise [RuntimeError] If no provider is found for the specified model
      desc 'chat', 'Start an interactive chat'
      option :model, aliases: '-m', desc: 'Specify the model to use'
      option :system, aliases: '-s', desc: 'Set a system prompt'
      option :continue, aliases: '-c', type: :boolean, desc: 'Continue the previous conversation'
      option :conversation, aliases: '--cid', desc: 'Continue a specific conversation by ID'
      option :no_stream, type: :boolean, desc: 'Disable streaming of tokens'
      option :option, aliases: '-o', type: :hash, desc: 'Set model-specific options'
      def chat
        model = options[:model] || 'gpt-3.5-turbo'
        provider_class = Durable::Llm::Providers.model_id_to_provider(model)

        raise "no provider found for model '#{model}'" if provider_class.nil? || provider_class.name.nil?

        provider_name = provider_class.name.split('::').last.downcase.to_sym
        client = Durable::Llm::Client.new(provider_name)

        conversation_id = options[:conversation] || (options[:continue] ? last_conversation_id : nil)
        conversation = conversation_id ? load_conversation(conversation_id) : nil

        messages = conversation ? conversation['messages'].dup : []
        messages << { role: 'system', content: options[:system] } if options[:system] && !conversation

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

          begin
            if options[:no_stream] || !client.stream?
              response = client.completion(**params)
              assistant_message = response.choices.first.to_s
              cli.say(assistant_message)
              messages << { role: 'assistant', content: assistant_message }
            else
              assistant_content = ''
              client.stream(**params) do |chunk|
                print chunk
                assistant_content += chunk
                $stdout.flush
              end
              puts # Add newline after streaming
              messages << { role: 'assistant', content: assistant_content }
            end

            # Save conversation after each exchange
            conversation_data = {
              'id' => conversation_id,
              'model' => model,
              'messages' => messages,
              'created_at' => conversation ? conversation['created_at'] : Time.now.iso8601
            }
            conversation_id = save_conversation(conversation_data)
          rescue Durable::Llm::Error => e
            cli.say("API Error: #{e.message}")
            next
          rescue StandardError => e
            cli.say("Unexpected error: #{e.message}")
            next
          end
        end
      end

      # List all available models from all providers
      #
      # @option options :options [Boolean] Show model-specific options for each model
      # @return [void] Outputs available models to stdout
      desc 'models', 'List available models'
      option :options, type: :boolean, desc: 'Show model options'
      def models
        cli = HighLine.new
        cli.say('Available models:')

        Durable::Llm::Providers.providers.each do |provider_sym|
          provider_class = Durable::Llm::Providers.provider_class_for(provider_sym)
          begin
            provider_models = provider_class.models
            cli.say("#{provider_sym.to_s.capitalize}:")
            provider_models.each do |model|
              cli.say("  #{model}")
              if options[:options]
                provider_options = provider_class.options
                cli.say("    Options: #{provider_options.join(', ')}")
              end
            end
          rescue StandardError => e
            cli.say("#{provider_sym.to_s.capitalize}: Error loading models - #{e.message}")
          end
        end
      end

      # List all saved conversations
      #
      # @return [void] Outputs list of saved conversations to stdout
      desc 'conversations', 'List saved conversations'
      def conversations
        cli = HighLine.new

        unless Dir.exist?(CONVERSATIONS_DIR)
          cli.say('No conversations found.')
          return
        end

        conversation_files = Dir.glob("#{CONVERSATIONS_DIR}/*.json").sort_by { |f| File.mtime(f) }.reverse

        if conversation_files.empty?
          cli.say('No conversations found.')
          return
        end

        cli.say('Saved conversations:')
        cli.say('')

        conversation_files.each do |file|
          id = File.basename(file, '.json')
          begin
            conversation = JSON.parse(File.read(file))
            model = conversation['model'] || 'unknown'
            message_count = conversation['messages']&.length || 0
            updated_at = conversation['updated_at'] ? Time.parse(conversation['updated_at']).strftime('%Y-%m-%d %H:%M') : 'unknown'

            marker = id == last_conversation_id ? ' *' : ''
            cli.say("#{id}#{marker} - #{model} (#{message_count} messages, updated #{updated_at})")
          rescue JSON::ParserError
            cli.say("#{id} - [corrupted conversation file]")
          end
        end

        cli.say('')
        cli.say('* indicates the last active conversation')
      end

      # Delete a saved conversation by ID
      #
      # @param id [String] The conversation ID to delete
      # @return [void] Outputs confirmation message to stdout
      desc 'delete_conversation ID', 'Delete a saved conversation'
      def delete_conversation(id)
        cli = HighLine.new

        path = conversation_file_path(id)
        if File.exist?(path)
          File.delete(path)
          cli.say("Deleted conversation #{id}")

          # Remove from last conversation if it was the last one
          File.delete(LAST_CONVERSATION_FILE) if last_conversation_id == id && File.exist?(LAST_CONVERSATION_FILE)
        else
          cli.say("Conversation #{id} not found")
        end
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
