# frozen_string_literal: true

ENV.delete_if { |key, _| key.start_with?("DLLM") }
require 'bundler/setup'

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "durable/llm"

Durable::Llm.configuration.clear

require "minitest/autorun"
