# OpenAI Example

This example demonstrates how to use the Durable-LLM gem with OpenAI's API.

## Basic Usage

```ruby
require 'durable/llm'

# Initialize the client
client = Durable::Llm::Client.new(:openai, api_key: 'your-api-key')

# Make a completion request
response = client.completion(
  model: 'gpt-3.5-turbo',
  messages: [
    { role: 'system', content: 'You are a helpful assistant.' },
    { role: 'user', content: 'What is the capital of France?' }
  ]
)

puts response.choices.first.message.content

# Output: Paris is the capital of France.
```

## Streaming

```ruby
client.stream(
  model: 'gpt-3.5-turbo',
  messages: [
    { role: 'system', content: 'You are a helpful assistant.' },
    { role: 'user', content: 'Tell me a short story about a robot.' }
  ]
) do |chunk|
  print chunk.to_s
end

# Output will be printed as it's received from the API
```

## Embeddings

```ruby
embedding_response = client.embed(
  model: 'text-embedding-ada-002',
  input: 'The quick brown fox jumps over the lazy dog'
)

puts embedding_response.embedding.first(5).inspect

# Output: [0.0023064255, -0.009327292, -0.0028842434, 0.022165427, -0.01085841]
```

## Configuration

You can configure the OpenAI provider globally:

```ruby
Durable::Llm.configure do |config|
  config.openai.api_key = 'your-api-key'
  config.openai.organization = 'your-organization-id' # Optional
end

# Now you can create a client without specifying the API key
client = Durable::Llm::Client.new(:openai)
```

## Error Handling

```ruby
begin
  response = client.completion(
    model: 'gpt-3.5-turbo',
    messages: [{ role: 'user', content: 'Hello!' }]
  )
rescue Durable::Llm::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
rescue Durable::Llm::APIError => e
  puts "API error occurred: #{e.message}"
end
```

This example covers basic usage, streaming, embeddings, configuration, and error handling for the OpenAI provider using the Durable-LLM gem.
