# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/cli'
require 'durable/llm/client'
require 'durable/llm/providers'
require 'highline'

class TestCLI < Minitest::Test
  def setup
    @cli = Durable::Llm::CLI.new
    @original_stdout = $stdout
    $stdout = StringIO.new
  end

  def teardown
    $stdout = @original_stdout
  end

  def test_prompt_command_basic
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).returns(false)
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: 'Hello world' }]
    ).returns(response_mock)

    response_mock.expects(:choices).returns([choice_mock])
    choice_mock.expects(:to_s).returns('Hello from AI')

    @cli.invoke(:prompt, ['Hello world'])

    assert_includes $stdout.string, 'Hello from AI'
  end

  def test_prompt_command_with_model_option
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-4').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).returns(false)
    client_mock.expects(:completion).with(
      model: 'gpt-4',
      messages: [{ role: 'user', content: 'Test prompt' }]
    ).returns(response_mock)

    response_mock.expects(:choices).returns([choice_mock])
    choice_mock.expects(:to_s).returns('Response from GPT-4')

    @cli.invoke(:prompt, ['Test prompt'], { model: 'gpt-4' })

    assert_includes $stdout.string, 'Response from GPT-4'
  end

  def test_prompt_command_with_system_prompt
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).returns(false)
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [
        { role: 'system', content: 'You are a helpful assistant' },
        { role: 'user', content: 'Hello' }
      ]
    ).returns(response_mock)

    response_mock.expects(:choices).returns([choice_mock])
    choice_mock.expects(:to_s).returns('Hello! How can I help you?')

    @cli.invoke(:prompt, ['Hello'], { system: 'You are a helpful assistant' })

    assert_includes $stdout.string, 'Hello! How can I help you?'
  end

  def test_prompt_command_with_streaming
    client_mock = mock('client')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).returns(true)
    client_mock.expects(:stream).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: 'Stream test' }]
    ).multiple_yields(['Hello'], [' '], ['world'])

    @cli.invoke(:prompt, ['Stream test'])

    assert_equal 'Hello world', $stdout.string
  end

  def test_prompt_command_no_stream_option
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).never
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: 'No stream' }]
    ).returns(response_mock)

    response_mock.expects(:choices).returns([choice_mock])
    choice_mock.expects(:to_s).returns('Regular response')

    @cli.invoke(:prompt, ['No stream'], { no_stream: true })

    assert_includes $stdout.string, 'Regular response'
  end

  def test_prompt_command_with_custom_options
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    client_mock.expects(:stream?).returns(false)
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: 'Test' }],
      temperature: '0.7',
      max_tokens: '100'
    ).returns(response_mock)

    response_mock.expects(:choices).returns([choice_mock])
    choice_mock.expects(:to_s).returns('Custom response')

    @cli.invoke(:prompt, ['Test'], { option: { temperature: '0.7', max_tokens: '100' } })

    assert_includes $stdout.string, 'Custom response'
  end

  def test_prompt_command_no_provider_found
    Durable::Llm::Providers.expects(:model_id_to_provider).with('unknown-model').returns(nil)

    assert_raises RuntimeError, "no provider found for model 'unknown-model'" do
      @cli.invoke(:prompt, ['Test'], { model: 'unknown-model' })
    end
  end

  def test_chat_command_basic
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    cli_mock.expects(:say).with('Chatting with gpt-3.5-turbo')
    cli_mock.expects(:say).with("Type 'exit' or 'quit' to exit")
    cli_mock.expects(:say).with("Type '!multi' to enter multiple lines, then '!end' to finish")

    chat_sequence = sequence('chat')

    cli_mock.expects(:ask).with('> ').returns('Hello').in_sequence(chat_sequence)

    client_mock.expects(:stream?).returns(false).in_sequence(chat_sequence)
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: 'Hello' }]
    ).returns(response_mock).in_sequence(chat_sequence)

    response_mock.expects(:choices).returns([choice_mock]).in_sequence(chat_sequence)
    choice_mock.expects(:to_s).returns('Hi there!').in_sequence(chat_sequence)
    cli_mock.expects(:say).with('Hi there!').in_sequence(chat_sequence)

    cli_mock.expects(:ask).with('> ').returns('exit').in_sequence(chat_sequence)

    @cli.invoke(:chat)
  end

  def test_chat_command_with_system_prompt
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-4').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    cli_mock.expects(:say).with('Chatting with gpt-4')
    cli_mock.expects(:say).with("Type 'exit' or 'quit' to exit")
    cli_mock.expects(:say).with("Type '!multi' to enter multiple lines, then '!end' to finish")

    chat_sequence = sequence('chat')

    cli_mock.expects(:ask).with('> ').returns('Test').in_sequence(chat_sequence)

    client_mock.expects(:stream?).returns(false).in_sequence(chat_sequence)
    client_mock.expects(:completion).with(
      model: 'gpt-4',
      messages: [
        { role: 'system', content: 'Be concise' },
        { role: 'user', content: 'Test' }
      ]
    ).returns(response_mock).in_sequence(chat_sequence)

    response_mock.expects(:choices).returns([choice_mock]).in_sequence(chat_sequence)
    choice_mock.expects(:to_s).returns('OK').in_sequence(chat_sequence)
    cli_mock.expects(:say).with('OK').in_sequence(chat_sequence)

    cli_mock.expects(:ask).with('> ').returns('quit').in_sequence(chat_sequence)

    @cli.invoke(:chat, [], { model: 'gpt-4', system: 'Be concise' })
  end

  def test_chat_command_multiline_input
    client_mock = mock('client')
    response_mock = mock('response')
    choice_mock = mock('choice')
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    Durable::Llm::Providers.expects(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Client.expects(:new).with(:openai).returns(client_mock)

    cli_mock.expects(:say).with('Chatting with gpt-3.5-turbo')
    cli_mock.expects(:say).with("Type 'exit' or 'quit' to exit")
    cli_mock.expects(:say).with("Type '!multi' to enter multiple lines, then '!end' to finish")

    chat_sequence = sequence('chat')

    cli_mock.expects(:ask).with('> ').returns('!multi').in_sequence(chat_sequence)
    cli_mock.expects(:ask).with("Enter multiple lines. Type '!end' to finish:").yields(mock_question = mock).returns("Line 1\nLine 2").in_sequence(chat_sequence)
    mock_question.expects(:gather=).with('!end')

    client_mock.expects(:stream?).returns(false).in_sequence(chat_sequence)
    client_mock.expects(:completion).with(
      model: 'gpt-3.5-turbo',
      messages: [{ role: 'user', content: "Line 1\nLine 2" }]
    ).returns(response_mock).in_sequence(chat_sequence)

    response_mock.expects(:choices).returns([choice_mock]).in_sequence(chat_sequence)
    choice_mock.expects(:to_s).returns('Multi-line response').in_sequence(chat_sequence)
    cli_mock.expects(:say).with('Multi-line response').in_sequence(chat_sequence)

    cli_mock.expects(:ask).with('> ').returns('exit').in_sequence(chat_sequence)

    @cli.invoke(:chat)
  end

  def test_models_command
    cli_mock = mock('highline')
    openai_mock = mock('openai_provider')
    anthropic_mock = mock('anthropic_provider')

    HighLine.expects(:new).returns(cli_mock)

    Durable::Llm::Providers.expects(:providers).returns(%i[openai anthropic])

    Durable::Llm::Providers.expects(:provider_class_for).with(:openai).returns(openai_mock)
    Durable::Llm::Providers.expects(:provider_class_for).with(:anthropic).returns(anthropic_mock)

    openai_mock.expects(:models).returns(['gpt-3.5-turbo', 'gpt-4'])
    anthropic_mock.expects(:models).returns(['claude-2.1', 'claude-instant'])

    cli_mock.expects(:say).with('Fetching available models...')
    cli_mock.expects(:say).with('')
    cli_mock.expects(:say).with('Openai:')
    cli_mock.expects(:say).with('  gpt-3.5-turbo')
    cli_mock.expects(:say).with('  gpt-4')
    cli_mock.expects(:say).with('Anthropic:')
    cli_mock.expects(:say).with('  claude-2.1')
    cli_mock.expects(:say).with('  claude-instant')

    @cli.invoke(:models)
  end

  def test_models_command_with_options_flag
    cli_mock = mock('highline')
    openai_mock = mock('openai_provider')

    HighLine.expects(:new).returns(cli_mock)

    Durable::Llm::Providers.expects(:providers).returns([:openai])
    Durable::Llm::Providers.expects(:provider_class_for).with(:openai).returns(openai_mock)
    openai_mock.expects(:models).returns(['gpt-3.5-turbo'])
    openai_mock.expects(:options).returns(%w[temperature max_tokens top_p frequency_penalty
                                             presence_penalty])

    cli_mock.expects(:say).with('Fetching available models...')
    cli_mock.expects(:say).with('')
    cli_mock.expects(:say).with('Openai:')
    cli_mock.expects(:say).with('  gpt-3.5-turbo')
    cli_mock.expects(:say).with('    Options: temperature, max_tokens, top_p, frequency_penalty, presence_penalty')

    @cli.invoke(:models, [], { options: true })
  end

  def test_conversations_command_no_conversations
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    Dir.expects(:exist?).with(Durable::Llm::CLI::CONVERSATIONS_DIR).returns(true)
    Dir.expects(:glob).with("#{Durable::Llm::CLI::CONVERSATIONS_DIR}/*.json").returns([])

    cli_mock.expects(:say).with('No conversations found.')

    @cli.invoke(:conversations)
  end

  def test_conversations_command_with_conversations
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    # Mock Dir.glob and file operations
    Dir.expects(:exist?).with(Durable::Llm::CLI::CONVERSATIONS_DIR).returns(true)
    conversation_file = "#{Durable::Llm::CLI::CONVERSATIONS_DIR}/abc123.json"
    Dir.expects(:glob).with("#{Durable::Llm::CLI::CONVERSATIONS_DIR}/*.json").returns([conversation_file])
    File.expects(:mtime).with(conversation_file).returns(Time.parse('2024-01-01 12:00:00'))
    File.expects(:read).with(conversation_file).returns('{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}],"updated_at":"2024-01-01T12:00:00Z"}')
    File.expects(:exist?).with(Durable::Llm::CLI::LAST_CONVERSATION_FILE).returns(true)
    File.expects(:read).with(Durable::Llm::CLI::LAST_CONVERSATION_FILE).returns('abc123')

    cli_mock.expects(:say).with('Saved conversations:')
    cli_mock.expects(:say).with('')
    cli_mock.expects(:say).with('abc123 * - gpt-4 (1 messages, updated 2024-01-01 12:00)')
    cli_mock.expects(:say).with('')
    cli_mock.expects(:say).with('* indicates the last active conversation')

    @cli.invoke(:conversations)
  end

  def test_delete_conversation_command
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    conversation_path = @cli.conversation_file_path('abc123')
    File.expects(:exist?).with(conversation_path).returns(true)
    File.expects(:delete).with(conversation_path)
    File.expects(:exist?).with(Durable::Llm::CLI::LAST_CONVERSATION_FILE).returns(true).twice
    File.expects(:read).with(Durable::Llm::CLI::LAST_CONVERSATION_FILE).returns('abc123')
    File.expects(:delete).with(Durable::Llm::CLI::LAST_CONVERSATION_FILE)

    cli_mock.expects(:say).with('Deleted conversation abc123')

    @cli.invoke(:delete_conversation, ['abc123'])
  end

  def test_delete_conversation_command_not_found
    cli_mock = mock('highline')

    HighLine.expects(:new).returns(cli_mock)

    File.expects(:exist?).with(@cli.conversation_file_path('nonexistent')).returns(false)

    cli_mock.expects(:say).with('Conversation nonexistent not found')

    @cli.invoke(:delete_conversation, ['nonexistent'])
  end
end
