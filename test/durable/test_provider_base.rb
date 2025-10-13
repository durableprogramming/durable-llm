# frozen_string_literal: true

require 'minitest/autorun'
require 'durable/llm/providers/base'

class TestProviderBase < Minitest::Test
  class TestBaseProvider < Durable::Llm::Providers::Base
    def default_api_key
      'test_api_key'
    end
  end

  def setup
    @provider = TestBaseProvider.new
  end

  def test_initialize_with_api_key
    provider = TestBaseProvider.new(api_key: 'custom_key')
    assert_equal 'custom_key', provider.api_key
  end

  def test_initialize_without_api_key_uses_default
    assert_equal 'test_api_key', @provider.api_key
  end

  def test_completion_raises_not_implemented
    assert_raises NotImplementedError do
      @provider.completion({})
    end
  end

  def test_models_raises_not_implemented
    assert_raises NotImplementedError do
      @provider.models
    end
  end

  def test_stream_raises_not_implemented
    assert_raises NotImplementedError do
      @provider.stream({}) {}
    end
  end

  def test_embedding_raises_not_implemented
    assert_raises NotImplementedError do
      @provider.embedding(model: 'test', input: 'test')
    end
  end

  def test_handle_response_raises_not_implemented
    assert_raises NotImplementedError do
      @provider.send(:handle_response, nil)
    end
  end

  def test_stream_class_method
    refute TestBaseProvider.stream?
  end

  def test_stream_instance_method
    refute @provider.stream?
  end

  def test_self_models_caching
    # Mock the new method to return a provider with models
    TestBaseProvider.stub :new, @provider do
      @provider.stub :models, ['model1', 'model2'] do
        models = TestBaseProvider.models
        assert_equal %w[model1 model2], models
      end
    end
  end
end
