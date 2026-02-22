#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/durable/llm'

# Simple calculator tool
def calculator(operation, a, b)
  case operation
  when 'add'
    a + b
  when 'subtract'
    a - b
  when 'multiply'
    a * b
  when 'divide'
    b.zero? ? 'Error: Division by zero' : a / b.to_f
  else
    'Unknown operation'
  end
end

# Tool definitions
tools = [
  {
    name: 'calculator',
    description: 'Performs basic arithmetic operations',
    input_schema: {
      type: 'object',
      properties: {
        operation: {
          type: 'string',
          enum: %w[add subtract multiply divide],
          description: 'The arithmetic operation to perform'
        },
        a: {
          type: 'number',
          description: 'First number'
        },
        b: {
          type: 'number',
          description: 'Second number'
        }
      },
      required: %w[operation a b]
    }
  }
]

# Initialize client (using Anthropic for tool support)
client = Durable::Llm::Client.new.with_provider(:anthropic).with_model('claude-sonnet-4-6')

# Start conversation
messages = [
  { role: 'user', content: 'What is 15 multiplied by 7, then add 23 to that result?' }
]

puts "User: #{messages.first[:content]}\n\n"

# Tool usage loop
max_iterations = 10
iteration = 0

loop do
  iteration += 1
  break if iteration > max_iterations

  # Make request with tools
  response = client.completion(
    messages: messages,
    tools: tools,
    max_tokens: 1024
  )

  # Add assistant's response to messages
  messages << {
    role: 'assistant',
    content: response.raw_response['content']
  }

  # Check if we got tool calls
  tool_uses = response.raw_response['content'].select { |block| block['type'] == 'tool_use' }

  if tool_uses.empty?
    # No more tool calls, we're done
    text_blocks = response.raw_response['content'].select { |block| block['type'] == 'text' }
    puts "Assistant: #{text_blocks.map { |b| b['text'] }.join("\n")}"
    break
  end

  # Process tool calls
  tool_results = tool_uses.map do |tool_use|
    tool_name = tool_use['name']
    tool_input = tool_use['input']

    puts "Tool call: #{tool_name}(#{tool_input.inspect})"

    # Execute the tool
    result = case tool_name
             when 'calculator'
               calculator(
                 tool_input['operation'],
                 tool_input['a'],
                 tool_input['b']
               )
             else
               'Unknown tool'
             end

    puts "Tool result: #{result}\n\n"

    {
      type: 'tool_result',
      tool_use_id: tool_use['id'],
      content: result.to_s
    }
  end

  # Add tool results to messages
  messages << {
    role: 'user',
    content: tool_results
  }
end

puts "\nConversation complete after #{iteration} iterations"

