# frozen_string_literal: true

require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm'
require 'durable/llm/providers'

class TestLlm < Minitest::Test
  def setup
    @original_config = Durable::Llm.configuration
    Durable::Llm.configuration = Durable::Llm::Configuration.new
  end

  def teardown
    Durable::Llm.configuration = @original_config
  end

  def test_configure
    Durable::Llm.configure do |config|
      config.default_provider = :openai
    end

    assert_equal :openai, Durable::Llm.configuration.default_provider
  end

  def test_config_alias
    assert_equal Durable::Llm.configuration, Durable::Llm.config
  end

  def test_load_from_env
    old = ENV['DLLM__OPENAI__API_KEY']
    ENV['DLLM__OPENAI__API_KEY'] = 'test_key'

    config = Durable::Llm::Configuration.new

    assert_equal 'test_key', config.openai.api_key
    ENV['DLLM__OPENAI__API_KEY'] = old
  end

  def test_load_from_datasette
    config = Durable::Llm::Configuration.new
    fake_config_data = { 'openai' => 'fake_api_key' }

    File.stubs(:exist?).returns(true)
    File.stubs(:read).returns(fake_config_data.to_json)
    JSON.stubs(:parse).returns(fake_config_data)

    config.load_from_datasette

    assert_equal 'fake_api_key', config.openai.api_key
  end

  def test_providers
    Durable::Llm::Providers.stubs(:providers).returns(%i[openai anthropic])
    providers = Durable::Llm::Providers.providers
    assert_includes providers, :openai
    assert_includes providers, :anthropic
  end

  def test_model_ids
    Durable::Llm::Providers.stubs(:model_ids).returns(['gpt-3.5-turbo', 'claude-2.1'])
    model_ids = Durable::Llm::Providers.model_ids
    assert_includes model_ids, 'gpt-3.5-turbo'
    assert_includes model_ids, 'claude-2.1'
  end

  def test_model_id_to_provider
    Durable::Llm::Providers.stubs(:model_id_to_provider).with('gpt-3.5-turbo').returns(Durable::Llm::Providers::OpenAI)
    Durable::Llm::Providers.stubs(:model_id_to_provider).with('claude-2.1').returns(Durable::Llm::Providers::Anthropic)

    provider_class = Durable::Llm::Providers.model_id_to_provider('gpt-3.5-turbo')
    assert_equal Durable::Llm::Providers::OpenAI, provider_class

    provider_class = Durable::Llm::Providers.model_id_to_provider('claude-2.1')
    assert_equal Durable::Llm::Providers::Anthropic, provider_class
  end
end
