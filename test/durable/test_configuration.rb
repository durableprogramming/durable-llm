# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'mocha/minitest'
require 'durable/llm/configuration'
require 'durable/llm/providers'

class TestConfiguration < Minitest::Test
  def setup
    @config = Durable::Llm::Configuration.new
  end

  def test_initialize_sets_default_provider
    assert_equal 'openai', @config.default_provider
  end

  def test_initialize_creates_empty_providers_hash
    assert_instance_of Hash, @config.providers
    assert_empty @config.providers
  end

  def test_initialize_loads_from_env
    old_env = ENV['DLLM__OPENAI__API_KEY']
    ENV['DLLM__OPENAI__API_KEY'] = 'test_key'

    config = Durable::Llm::Configuration.new
    assert_equal 'test_key', config.openai.api_key

    ENV['DLLM__OPENAI__API_KEY'] = old_env
  end

  def test_clear_resets_providers_and_default_provider
    @config.openai = { api_key: 'test' }
    @config.default_provider = 'anthropic'

    @config.clear

    assert_empty @config.providers
    assert_equal 'openai', @config.default_provider
  end

  def test_clear_reloads_from_env
    old_env = ENV['DLLM__ANTHROPIC__API_KEY']
    ENV['DLLM__ANTHROPIC__API_KEY'] = 'env_key'

    @config.clear

    assert_equal 'env_key', @config.anthropic.api_key

    ENV['DLLM__ANTHROPIC__API_KEY'] = old_env
  end

  def test_load_from_env_parses_dllm_variables
    old_env = {}
    %w[DLLM__OPENAI__API_KEY DLLM__ANTHROPIC__MODEL DLLM__GOOGLE__API_KEY].each do |key|
      old_env[key] = ENV[key]
    end

    ENV['DLLM__OPENAI__API_KEY'] = 'openai_key'
    ENV['DLLM__ANTHROPIC__MODEL'] = 'claude-3'
    ENV['DLLM__GOOGLE__API_KEY'] = 'google_key'

    config = Durable::Llm::Configuration.new

    assert_equal 'openai_key', config.openai.api_key
    assert_equal 'claude-3', config.anthropic.model
    assert_equal 'google_key', config.google.api_key

    old_env.each { |key, value| ENV[key] = value }
  end

  def test_load_from_env_handles_malformed_variables
    old_env = ENV['DLLM__MALFORMED']
    ENV['DLLM__MALFORMED'] = 'should_be_ignored'

    config = Durable::Llm::Configuration.new

    # Should not crash and should ignore malformed variables (missing setting part)
    # method_missing creates OpenStruct for any provider name
    assert_instance_of OpenStruct, config.malformed

    ENV['DLLM__MALFORMED'] = old_env
  end

  def test_load_from_datasette_with_existing_file
    fake_config_data = { 'openai' => 'fake_api_key', 'anthropic' => 'anthropic_key' }

    File.stubs(:exist?).returns(true)
    File.stubs(:read).returns(fake_config_data.to_json)
    JSON.stubs(:parse).returns(fake_config_data)

    Durable::Llm::Providers.stubs(:providers).returns(%i[openai anthropic])

    @config.load_from_datasette

    assert_equal 'fake_api_key', @config.openai.api_key
    assert_equal 'anthropic_key', @config.anthropic.api_key
  end

  def test_load_from_datasette_with_missing_file
    File.stubs(:exist?).returns(false)

    @config.load_from_datasette

    # Should not raise error and should not modify config
    assert_nil @config.openai.api_key
  end

  def test_load_from_datasette_with_invalid_json
    File.stubs(:exist?).returns(true)
    File.stubs(:read).returns('invalid json')
    JSON.stubs(:parse).raises(JSON::ParserError.new('invalid'))

    assert_output(nil, /Error parsing Datasette LLM configuration file/) do
      @config.load_from_datasette
    end
  end

  def test_load_from_datasette_with_file_error
    File.stubs(:exist?).returns(true)
    File.stubs(:read).raises(Errno::EACCES.new('permission denied'))

    assert_output(nil, /Error loading Datasette LLM configuration/) do
      @config.load_from_datasette
    end
  end

  def test_load_from_datasette_ignores_missing_providers
    fake_config_data = { 'nonexistent' => 'key' }

    File.stubs(:exist?).returns(true)
    File.stubs(:read).returns(fake_config_data.to_json)
    JSON.stubs(:parse).returns(fake_config_data)

    Durable::Llm::Providers.stubs(:providers).returns(%i[openai anthropic])

    @config.load_from_datasette

    # Should not set anything since 'nonexistent' is not in providers list
    assert_nil @config.openai.api_key
  end

  def test_method_missing_getter_creates_provider_config
    config = @config.openai

    assert_instance_of OpenStruct, config
    assert_equal config, @config.providers[:openai]
  end

  def test_method_missing_getter_returns_existing_config
    @config.providers[:openai] = OpenStruct.new(api_key: 'existing')

    config = @config.openai

    assert_equal 'existing', config.api_key
  end

  def test_method_missing_setter_with_hash_merges_values
    @config.openai = { api_key: 'test_key', model: 'gpt-4' }

    assert_equal 'test_key', @config.openai.api_key
    assert_equal 'gpt-4', @config.openai.model
  end

  def test_method_missing_setter_with_hash_preserves_existing_values
    @config.openai.api_key = 'existing_key'
    @config.openai = { model: 'gpt-4' }

    assert_equal 'existing_key', @config.openai.api_key
    assert_equal 'gpt-4', @config.openai.model
  end

  def test_method_missing_setter_with_object_replaces_config
    custom_struct = OpenStruct.new(api_key: 'custom_key', custom_field: 'value')
    @config.openai = custom_struct

    assert_equal custom_struct, @config.openai
    assert_equal 'custom_key', @config.openai.api_key
    assert_equal 'value', @config.openai.custom_field
  end

  def test_method_missing_setter_creates_provider_if_not_exists
    @config.openai = { api_key: 'test' }

    assert @config.providers.key?(:openai)
    assert_equal 'test', @config.openai.api_key
  end

  def test_respond_to_missing_always_returns_true
    assert @config.respond_to?(:openai)
    assert @config.respond_to?(:openai=)
    assert @config.respond_to?(:nonexistent_method)
    assert @config.respond_to?(:another=)
  end

  def test_default_provider_accessor
    @config.default_provider = 'anthropic'
    assert_equal 'anthropic', @config.default_provider
  end

  def test_providers_reader_returns_hash
    assert_instance_of Hash, @config.providers

    @config.openai.api_key = 'test'
    assert_equal 'test', @config.providers[:openai].api_key
  end

  def test_configuration_isolation
    config1 = Durable::Llm::Configuration.new
    config2 = Durable::Llm::Configuration.new

    config1.openai = { api_key: 'key1' }
    config2.openai = { api_key: 'key2' }

    assert_equal 'key1', config1.openai.api_key
    assert_equal 'key2', config2.openai.api_key
  end

  def test_dynamic_provider_names
    # Test with various provider names
    @config.test_provider = { api_key: 'test' }
    @config.anotherprovider.api_key = 'another'

    assert_equal 'test', @config.test_provider.api_key
    assert_equal 'another', @config.anotherprovider.api_key
  end

  def test_provider_config_persistence
    @config.openai.api_key = 'persistent_key'
    @config.openai.model = 'gpt-4'

    # Access again to ensure persistence
    assert_equal 'persistent_key', @config.openai.api_key
    assert_equal 'gpt-4', @config.openai.model
  end
end
