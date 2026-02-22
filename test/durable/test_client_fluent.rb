# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/client'
require 'durable/llm/providers'

class TestClientFluent < Minitest::Test
  def setup
    @original_config = Durable::Llm.configuration
    Durable::Llm.configuration = Durable::Llm::Configuration.new
    @mock_provider = mock('provider')
  end

  def teardown
    Durable::Llm.configuration = @original_config
  end

  def test_initialize_without_provider
    client = Durable::Llm::Client.new
    assert_nil client.instance_variable_get(:@provider)
  end

  def test_with_provider
    client = Durable::Llm::Client.new
    result = client.with_provider(:openai)

    assert_equal client, result
    assert_instance_of Durable::Llm::Providers::OpenAI, client.provider
  end

  def test_with_provider_chaining
    client = Durable::Llm::Client.new
      .with_provider(:openai)
      .with_model('gpt-4')

    assert_instance_of Durable::Llm::Providers::OpenAI, client.provider
    assert_equal 'gpt-4', client.model
  end

  def test_with_provider_empty_raises_error
    client = Durable::Llm::Client.new

    error = assert_raises(ArgumentError) do
      client.with_provider(nil)
    end
    assert_match(/Please specify a provider name/, error.message)
  end

  def test_with_model
    client = Durable::Llm::Client.new(:openai)
    result = client.with_model('gpt-4')

    assert_equal client, result
    assert_equal 'gpt-4', client.model
  end

  def test_with_temperature
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entry(:temperature, 0.7))
      .returns(mock('response'))

    client.with_temperature(0.7).completion(messages: [])
  end

  def test_with_max_tokens
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entry(:max_tokens, 500))
      .returns(mock('response'))

    client.with_max_tokens(500).completion(messages: [])
  end

  def test_with_tools
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    tools = [{ type: 'function', function: { name: 'test' } }]

    @mock_provider.expects(:completion)
      .with(has_entry(:tools, tools))
      .returns(mock('response'))

    client.with_tools(tools).completion(messages: [])
  end

  def test_with_tool_choice
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entry(:tool_choice, 'auto'))
      .returns(mock('response'))

    client.with_tool_choice('auto').completion(messages: [])
  end

  def test_with_system
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entry(:system, 'You are helpful'))
      .returns(mock('response'))

    client.with_system('You are helpful').completion(messages: [])
  end

  def test_with_top_p
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entry(:top_p, 0.9))
      .returns(mock('response'))

    client.with_top_p(0.9).completion(messages: [])
  end

  def test_with_stop
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    stop_sequences = ['\n\n', 'END']

    @mock_provider.expects(:completion)
      .with(has_entry(:stop, stop_sequences))
      .returns(mock('response'))

    client.with_stop(stop_sequences).completion(messages: [])
  end

  def test_fluent_chaining_multiple
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    @mock_provider.expects(:completion)
      .with(has_entries(
        temperature: 0.7,
        max_tokens: 500,
        top_p: 0.9
      ))
      .returns(mock('response'))

    client
      .with_temperature(0.7)
      .with_max_tokens(500)
      .with_top_p(0.9)
      .completion(messages: [])
  end

  def test_fluent_settings_cleared_after_use
    client = Durable::Llm::Client.new(:openai)
    client.instance_variable_set(:@provider, @mock_provider)

    # First call with settings
    @mock_provider.expects(:completion)
      .with(has_entry(:temperature, 0.7))
      .returns(mock('response'))

    client.with_temperature(0.7).completion(messages: [])

    # Second call without settings should not have temperature
    @mock_provider.expects(:completion)
      .with(Not(has_key(:temperature)))
      .returns(mock('response'))

    client.completion(messages: [])
  end

  def test_completion_without_provider_raises_error
    client = Durable::Llm::Client.new

    error = assert_raises(RuntimeError) do
      client.completion(messages: [])
    end
    assert_match(/No provider set/, error.message)
  end

  def test_stream_without_provider_raises_error
    client = Durable::Llm::Client.new

    error = assert_raises(RuntimeError) do
      client.stream(messages: []) {}
    end
    assert_match(/No provider set/, error.message)
  end

  def test_stream_returns_false_without_provider
    client = Durable::Llm::Client.new
    assert_equal false, client.stream?
  end
end
