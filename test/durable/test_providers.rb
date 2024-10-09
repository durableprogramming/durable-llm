require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/providers'
require 'durable/llm/providers/huggingface'

class TestProviders < Minitest::Test
  def setup
    @original_providers = Durable::Llm::Providers.instance_variable_get(:@provider_list)
    Durable::Llm::Providers.instance_variable_set(:@provider_list, nil)
  end

  def teardown
    Durable::Llm::Providers.instance_variable_set(:@provider_list, @original_providers)
  end

  def test_providers
    Durable::Llm::Providers.stubs(:constants).returns([:OpenAI, :Anthropic, :Huggingface, :Base])
    Durable::Llm::Providers.const_get(:OpenAI).stubs(:name).returns('Durable::Llm::Providers::OpenAI')
    Durable::Llm::Providers.const_get(:Anthropic).stubs(:name).returns('Durable::Llm::Providers::Anthropic')
    Durable::Llm::Providers.const_get(:Huggingface).stubs(:name).returns('Durable::Llm::Providers::Huggingface')
    Durable::Llm::Providers.const_get(:Base).stubs(:name).returns('Durable::Llm::Providers::Base')

    providers = Durable::Llm::Providers.providers
    assert_includes providers, :openai
    assert_includes providers, :anthropic
    assert_includes providers, :huggingface
    refute_includes providers, :base
  end

  def test_model_ids
    Durable::Llm::Providers.stubs(:providers).returns([:openai, :anthropic, :huggingface])
    Durable::Llm::Providers::OpenAI.stubs(:models).returns(['gpt-3.5-turbo', 'gpt-4'])
    Durable::Llm::Providers::Anthropic.stubs(:models).returns(['claude-2.1', 'claude-instant-1.2'])
    Durable::Llm::Providers::Huggingface.stubs(:models).returns(['gpt2', 'bert-base-uncased'])

    model_ids = Durable::Llm::Providers.model_ids
    assert_includes model_ids, 'gpt-3.5-turbo'
    assert_includes model_ids, 'gpt-4'
    assert_includes model_ids, 'claude-2.1'
    assert_includes model_ids, 'claude-instant-1.2'
    assert_includes model_ids, 'gpt2'
    assert_includes model_ids, 'bert-base-uncased'
  end

  def test_model_id_to_provider
    Durable::Llm::Providers.stubs(:providers).returns([:openai, :anthropic, :huggingface])
    Durable::Llm::Providers::OpenAI.stubs(:models).returns(['gpt-3.5-turbo', 'gpt-4'])
    Durable::Llm::Providers::Anthropic.stubs(:models).returns(['claude-2.1', 'claude-instant-1.2'])
    Durable::Llm::Providers::Huggingface.stubs(:models).returns(['gpt2', 'bert-base-uncased'])

    assert_equal Durable::Llm::Providers::OpenAI, Durable::Llm::Providers.model_id_to_provider('gpt-3.5-turbo')
    assert_equal Durable::Llm::Providers::Anthropic, Durable::Llm::Providers.model_id_to_provider('claude-2.1')
    assert_equal Durable::Llm::Providers::Huggingface, Durable::Llm::Providers.model_id_to_provider('gpt2')
    assert_nil Durable::Llm::Providers.model_id_to_provider('nonexistent-model')
  end

  def test_provider_aliases
    assert_equal Durable::Llm::Providers::OpenAI, Durable::Llm::Providers::Openai
    assert_equal Durable::Llm::Providers::Anthropic, Durable::Llm::Providers::Claude
    assert_equal Durable::Llm::Providers::Anthropic, Durable::Llm::Providers::Claude3
  end
end
