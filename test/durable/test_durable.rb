# frozen_string_literal: true

require 'minitest/autorun'
require 'durable'

class TestDurable < Minitest::Test
  def test_module_exists
    assert_kind_of Module, Durable
  end

  def test_llm_autoload
    # Test that Llm can be autoloaded
    assert_kind_of Module, Durable::Llm
  end

  def test_llm_functionality
    # Test that the autoloaded Llm module works
    assert_respond_to Durable::Llm, :configure
    assert_respond_to Durable::Llm, :new
  end
end
