# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'ostruct'
require 'durable/llm/response_helpers'

class TestResponseHelpers < Minitest::Test
  def setup
    @sample_response = OpenStruct.new(
      choices: [
        OpenStruct.new(
          message: OpenStruct.new(content: 'Hello, world!'),
          finish_reason: 'stop'
        )
      ],
      usage: OpenStruct.new(
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15
      ),
      model: 'gpt-4'
    )

    @multi_choice_response = OpenStruct.new(
      choices: [
        OpenStruct.new(message: OpenStruct.new(content: 'First response')),
        OpenStruct.new(message: OpenStruct.new(content: 'Second response')),
        OpenStruct.new(message: OpenStruct.new(content: 'Third response'))
      ]
    )

    @truncated_response = OpenStruct.new(
      choices: [
        OpenStruct.new(
          message: OpenStruct.new(content: 'Truncated text'),
          finish_reason: 'length'
        )
      ]
    )
  end

  def test_extract_content_from_valid_response
    content = Durable::Llm::ResponseHelpers.extract_content(@sample_response)
    assert_equal 'Hello, world!', content
  end

  def test_extract_content_from_nil_response
    content = Durable::Llm::ResponseHelpers.extract_content(nil)
    assert_nil content
  end

  def test_extract_content_from_response_without_choices
    response = OpenStruct.new(usage: {})
    content = Durable::Llm::ResponseHelpers.extract_content(response)
    assert_nil content
  end

  def test_extract_content_from_empty_choices
    response = OpenStruct.new(choices: [])
    content = Durable::Llm::ResponseHelpers.extract_content(response)
    assert_nil content
  end

  def test_extract_content_from_choice_without_message
    response = OpenStruct.new(choices: [OpenStruct.new(finish_reason: 'stop')])
    content = Durable::Llm::ResponseHelpers.extract_content(response)
    assert_nil content
  end

  def test_extract_content_from_message_without_content
    response = OpenStruct.new(
      choices: [OpenStruct.new(message: OpenStruct.new(role: 'assistant'))]
    )
    content = Durable::Llm::ResponseHelpers.extract_content(response)
    assert_nil content
  end

  def test_all_contents_from_multi_choice_response
    contents = Durable::Llm::ResponseHelpers.all_contents(@multi_choice_response)
    assert_equal 3, contents.length
    assert_equal 'First response', contents[0]
    assert_equal 'Second response', contents[1]
    assert_equal 'Third response', contents[2]
  end

  def test_all_contents_from_nil_response
    contents = Durable::Llm::ResponseHelpers.all_contents(nil)
    assert_equal [], contents
  end

  def test_all_contents_filters_invalid_choices
    response = OpenStruct.new(
      choices: [
        OpenStruct.new(message: OpenStruct.new(content: 'Valid')),
        OpenStruct.new(finish_reason: 'stop'), # No message
        OpenStruct.new(message: OpenStruct.new(content: 'Also valid'))
      ]
    )
    contents = Durable::Llm::ResponseHelpers.all_contents(response)
    assert_equal 2, contents.length
    assert_equal ['Valid', 'Also valid'], contents
  end

  def test_token_usage_from_valid_response
    usage = Durable::Llm::ResponseHelpers.token_usage(@sample_response)
    assert_equal 10, usage[:prompt_tokens]
    assert_equal 5, usage[:completion_tokens]
    assert_equal 15, usage[:total_tokens]
  end

  def test_token_usage_from_nil_response
    usage = Durable::Llm::ResponseHelpers.token_usage(nil)
    assert_nil usage
  end

  def test_token_usage_from_response_without_usage
    response = OpenStruct.new(choices: [])
    usage = Durable::Llm::ResponseHelpers.token_usage(response)
    assert_nil usage
  end

  def test_finish_reason_from_valid_response
    reason = Durable::Llm::ResponseHelpers.finish_reason(@sample_response)
    assert_equal 'stop', reason
  end

  def test_finish_reason_from_truncated_response
    reason = Durable::Llm::ResponseHelpers.finish_reason(@truncated_response)
    assert_equal 'length', reason
  end

  def test_finish_reason_from_nil_response
    reason = Durable::Llm::ResponseHelpers.finish_reason(nil)
    assert_nil reason
  end

  def test_finish_reason_from_empty_choices
    response = OpenStruct.new(choices: [])
    reason = Durable::Llm::ResponseHelpers.finish_reason(response)
    assert_nil reason
  end

  def test_truncated_returns_true_for_length_finish_reason
    assert Durable::Llm::ResponseHelpers.truncated?(@truncated_response)
  end

  def test_truncated_returns_false_for_stop_finish_reason
    refute Durable::Llm::ResponseHelpers.truncated?(@sample_response)
  end

  def test_truncated_returns_false_for_nil_response
    refute Durable::Llm::ResponseHelpers.truncated?(nil)
  end

  def test_to_hash_returns_complete_hash
    hash = Durable::Llm::ResponseHelpers.to_hash(@sample_response)

    assert_equal 'Hello, world!', hash[:content]
    assert_equal 'stop', hash[:finish_reason]
    assert_equal 10, hash[:tokens][:prompt_tokens]
    assert_equal 5, hash[:tokens][:completion_tokens]
    assert_equal 15, hash[:tokens][:total_tokens]
    assert_equal ['Hello, world!'], hash[:all_contents]
  end

  def test_to_hash_with_multi_choice_response
    hash = Durable::Llm::ResponseHelpers.to_hash(@multi_choice_response)

    assert_equal 'First response', hash[:content]
    assert_equal ['First response', 'Second response', 'Third response'], hash[:all_contents]
  end

  def test_model_used_from_valid_response
    model = Durable::Llm::ResponseHelpers.model_used(@sample_response)
    assert_equal 'gpt-4', model
  end

  def test_model_used_from_nil_response
    model = Durable::Llm::ResponseHelpers.model_used(nil)
    assert_nil model
  end

  def test_model_used_from_response_without_model
    response = OpenStruct.new(choices: [])
    model = Durable::Llm::ResponseHelpers.model_used(response)
    assert_nil model
  end

  def test_estimate_cost_for_gpt_4
    response = OpenStruct.new(
      model: 'gpt-4',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)

    # Cost = (1000 * 0.03/1000) + (500 * 0.06/1000) = 0.03 + 0.03 = 0.06
    assert_in_delta 0.06, cost, 0.001
  end

  def test_estimate_cost_for_gpt_4_turbo
    response = OpenStruct.new(
      model: 'gpt-4-turbo',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)

    # Cost = (1000 * 0.01/1000) + (500 * 0.03/1000) = 0.01 + 0.015 = 0.025
    assert_in_delta 0.025, cost, 0.001
  end

  def test_estimate_cost_for_gpt_35_turbo
    response = OpenStruct.new(
      model: 'gpt-3.5-turbo',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)

    # Cost = (1000 * 0.0015/1000) + (500 * 0.002/1000) = 0.0015 + 0.001 = 0.0025
    assert_in_delta 0.0025, cost, 0.0001
  end

  def test_estimate_cost_for_claude_3_opus
    response = OpenStruct.new(
      model: 'claude-3-opus-20240229',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)

    # Cost = (1000 * 0.015/1000) + (500 * 0.075/1000) = 0.015 + 0.0375 = 0.0525
    assert_in_delta 0.0525, cost, 0.001
  end

  def test_estimate_cost_for_claude_3_sonnet
    response = OpenStruct.new(
      model: 'claude-3-sonnet-20240229',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)

    # Cost = (1000 * 0.003/1000) + (500 * 0.015/1000) = 0.003 + 0.0075 = 0.0105
    assert_in_delta 0.0105, cost, 0.001
  end

  def test_estimate_cost_with_explicit_model_parameter
    response = OpenStruct.new(
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response, 'gpt-4')

    assert_in_delta 0.06, cost, 0.001
  end

  def test_estimate_cost_returns_nil_for_unknown_model
    response = OpenStruct.new(
      model: 'unknown-model',
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)
    assert_nil cost
  end

  def test_estimate_cost_returns_nil_without_usage
    response = OpenStruct.new(model: 'gpt-4')
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)
    assert_nil cost
  end

  def test_estimate_cost_returns_nil_without_model
    response = OpenStruct.new(
      usage: OpenStruct.new(
        prompt_tokens: 1000,
        completion_tokens: 500,
        total_tokens: 1500
      )
    )
    cost = Durable::Llm::ResponseHelpers.estimate_cost(response)
    assert_nil cost
  end
end
