# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/client'
require 'durable/llm/providers'

class TestClient < Minitest::Test
  def setup
    @original_config = Durable::Llm.configuration
    Durable::Llm.configuration = Durable::Llm::Configuration.new
    @mock_provider = mock('provider')
    @client = Durable::Llm::Client.new(:openai)
    @client.instance_variable_set(:@provider, @mock_provider)
  end

  def teardown
    Durable::Llm.configuration = @original_config
  end

  def test_initialize_with_provider_name
    client = Durable::Llm::Client.new(:openai)
    assert_instance_of Durable::Llm::Providers::OpenAI, client.provider
  end

  def test_initialize_with_model_option
    client = Durable::Llm::Client.new(:openai, model: 'gpt-4')
    assert_equal 'gpt-4', client.model
  end

  def test_initialize_with_string_model_option
    client = Durable::Llm::Client.new(:openai, 'model' => 'gpt-4')
    assert_equal 'gpt-4', client.model
  end

  def test_default_params
    client = Durable::Llm::Client.new(:openai, model: 'gpt-4')
    expected = { model: 'gpt-4' }
    assert_equal expected, client.default_params
  end

  def test_default_params_without_model
    client = Durable::Llm::Client.new(:openai)
    assert_equal({}, client.default_params)
  end

  def test_quick_complete
    mock_response = mock('response')
    mock_choice = mock('choice')
    mock_message = mock('message')

    mock_message.expects(:content).returns('Hello world')
    mock_choice.expects(:message).returns(mock_message)
    mock_response.expects(:choices).returns([mock_choice])

    @mock_provider.expects(:completion).with({ messages: [{ role: 'user', content: 'Hello' }] }).returns(mock_response)

    result = @client.quick_complete('Hello')
    assert_equal 'Hello world', result
  end

  def test_quick_complete_empty_choices
    mock_response = mock('response')
    mock_response.expects(:choices).returns([])

    @mock_provider.expects(:completion).with({ messages: [{ role: 'user', content: 'Hello' }] }).returns(mock_response)

    assert_raises(IndexError, 'No completion choices returned') do
      @client.quick_complete('Hello')
    end
  end

  def test_quick_complete_no_message
    mock_response = mock('response')
    mock_choice = mock('choice')

    mock_choice.expects(:message).returns(nil)
    mock_response.expects(:choices).returns([mock_choice])

    @mock_provider.expects(:completion).with({ messages: [{ role: 'user', content: 'Hello' }] }).returns(mock_response)

    assert_raises(NoMethodError, 'Response choice has no message') do
      @client.quick_complete('Hello')
    end
  end

  def test_quick_complete_no_content
    mock_response = mock('response')
    mock_choice = mock('choice')
    mock_message = mock('message')

    mock_message.expects(:content).returns(nil)
    mock_choice.expects(:message).returns(mock_message)
    mock_response.expects(:choices).returns([mock_choice])

    @mock_provider.expects(:completion).with({ messages: [{ role: 'user', content: 'Hello' }] }).returns(mock_response)

    assert_raises(NoMethodError, 'Response message has no content') do
      @client.quick_complete('Hello')
    end
  end

  def test_completion
    params = { messages: [{ role: 'user', content: 'Hello' }] }
    mock_response = mock('response')

    @mock_provider.expects(:completion).with(params).returns(mock_response)

    result = @client.completion(params)
    assert_equal mock_response, result
  end

  def test_chat
    params = { messages: [{ role: 'user', content: 'Hello' }] }
    mock_response = mock('response')

    @mock_provider.expects(:completion).with(params).returns(mock_response)

    result = @client.chat(params)
    assert_equal mock_response, result
  end

  def test_embed
    params = { model: 'text-embedding-ada-002', input: 'Hello world' }
    mock_response = mock('response')

    @mock_provider.expects(:embedding).with(**params).returns(mock_response)

    result = @client.embed(params)
    assert_equal mock_response, result
  end

  def test_embed_not_supported
    params = { model: 'text-embedding-ada-002', input: 'Hello world' }

    @mock_provider.expects(:embedding).with(**params).raises(NotImplementedError)

    error = assert_raises(NotImplementedError) do
      @client.embed(params)
    end
    assert_match(/does not support embeddings/, error.message)
  end

  def test_stream
    params = { messages: [{ role: 'user', content: 'Hello' }] }
    block_called = false

    @mock_provider.expects(:stream).with(params).yields('chunk')

    @client.stream(params) do |chunk|
      assert_equal 'chunk', chunk
      block_called = true
    end

    assert block_called
  end

  def test_stream_not_supported
    params = { messages: [{ role: 'user', content: 'Hello' }] }

    @mock_provider.expects(:stream).with(params).raises(NotImplementedError)

    error = assert_raises(NotImplementedError) do
      @client.stream(params) {}
    end
    assert_match(/does not support streaming/, error.message)
  end

  def test_stream?
    @mock_provider.expects(:stream?).returns(true)
    assert @client.stream?
  end

  def test_process_params_with_model
    @client.instance_variable_set(:@model, 'gpt-4')
    params = { temperature: 0.5 }
    expected = { model: 'gpt-4', temperature: 0.5 }

    result = @client.send(:process_params, params)
    assert_equal expected, result
  end

  def test_process_params_without_model
    @client.instance_variable_set(:@model, nil)
    params = { temperature: 0.5 }
    expected = { temperature: 0.5 }

    result = @client.send(:process_params, params)
    assert_equal expected, result
  end

  def test_provider_class_for_special_cases
    # Test that provider_class_for is used for special cases
    client = Durable::Llm::Client.new(:deepseek)
    assert_instance_of Durable::Llm::Providers::DeepSeek, client.provider
  end
end
