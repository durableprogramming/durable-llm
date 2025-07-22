# frozen_string_literal: true

require 'durable/llm'
require 'durable/llm/client'

client = Durable::Llm::Client.new(:openai, model: 'gpt-4')

response = client.quick_complete("What's the capital of California?")

puts response
