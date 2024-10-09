Here's the content for the file examples/anthropic.md with a line-by-line explanation of the script:

# Anthropic Example

This example demonstrates how to use the Durable-LLM gem with Anthropic's API.

## Basic Usage

```ruby
# Import the Durable-LLM library
require 'durable/llm'

# Initialize the client with the Anthropic provider
# You can pass the API key directly or set it in the environment variable ANTHROPIC_API_KEY
client = Durable::Llm::Client.new(:anthropic, api_key: 'your-api-key')

# Make a completion request
response = client.completion(
  # Specify the Anthropic model to use
  model: 'claude-3-5-sonnet-20240620',
  # Provide the messages for the conversation
  messages: [
    { role: 'user', content: 'What is the capital of France?' }
  ],
  # Set the maximum number of tokens for the response (optional). Defaults to 1024.
  max_tokens: 100
)

# Print the response content
puts response.choices.first.message.content

# Output: Paris is the capital of France.
```

## Streaming

```ruby
# Use the stream method for real-time responses
client.stream(
  model: 'claude-3-5-sonnet-20240620',
  messages: [
    { role: 'user', content: 'Tell me a short story about a robot.' }
  ],
  max_tokens: 200
) do |chunk|
  # Print each chunk of the response as it's received
  print chunk.to_s
end

# Output will be printed as it's received from the API
```

## Configuration

You can configure the Anthropic provider globally:

```ruby
# Set up global configuration for the Anthropic provider
Durable::Llm.configure do |config|
  config.anthropic.api_key = 'your-api-key'
end

# Create a client using the global configuration
client = Durable::Llm::Client.new(:anthropic)
```

## Error Handling

```ruby
begin
  # Attempt to make a completion request
  response = client.completion(
    model: 'claude-3-5-sonnet-20240620',
    messages: [{ role: 'user', content: 'Hello!' }]
  )
rescue Durable::Llm::RateLimitError => e
  # Handle rate limit errors
  puts "Rate limit exceeded: #{e.message}"
rescue Durable::Llm::APIError => e
  # Handle general API errors
  puts "API error occurred: #{e.message}"
end
```

This example covers basic usage, streaming, configuration, and error handling for the Anthropic provider using the Durable-LLM gem. Note that Anthropic's API doesn't support embeddings, so that functionality is not included in this example.
