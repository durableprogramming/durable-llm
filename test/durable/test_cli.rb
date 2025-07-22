# frozen_string_literal: true

require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/cli'
require_relative '../mocks/mock_provider'

class TestCLI < Minitest::Test
  def setup
    @cli = Durable::Llm::CLI.new
    @original_providers = Durable::Llm::Providers.providers
    Durable::Llm::Providers.stubs(:providers).returns([:mock])
    Durable::Llm::Providers.stubs(:const_get).with('Mock').returns(Durable::Llm::Providers::MockProvider)
    Durable::Llm::Providers.stubs(:model_id_to_provider).returns(Durable::Llm::Providers::MockProvider)
  end

  def teardown
    Durable::Llm::Providers.unstub(:providers)
    Durable::Llm::Providers.unstub(:const_get)
    Durable::Llm::Providers.unstub(:model_id_to_provider)
  end

  def test_prompt
    mock_client = Durable::Llm::Providers::MockProvider.new
    Durable::Llm::Client.stubs(:new).returns(mock_client)

    out, err = capture_io do
      @cli.prompt('Test prompt')
    end

    assert_equal 'Mock stream response', out.strip
    assert_empty err
  end

  def test_chat
    mock_client = Durable::Llm::Providers::MockProvider.new
    Durable::Llm::Client.stubs(:new).returns(mock_client)

    HighLine.any_instance.stubs(:ask).returns('Test input', 'exit')

    out, err = capture_io do
      @cli.chat
    end

    assert_includes out, 'Chatting with gpt-3.5-turbo'
    assert_includes out, 'Mock completion response'
    assert_empty err
  end

  def test_models
    out, err = capture_io do
      @cli.models
    end

    assert_includes out, 'Available models:'
    assert_includes out, 'Mock:'
    assert_includes out, 'mock-model-1'
    assert_includes out, 'mock-model-2'
    assert_empty err
  end
end
