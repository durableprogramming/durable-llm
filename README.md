# Durable-LLM

Durable-LLM is a Ruby gem providing a unified interface for interacting with multiple Large Language Model APIs. It simplifies the integration of AI capabilities into Ruby applications by offering a consistent way to access various LLM providers.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'durable-llm'
```

And then execute:

```
$ bundle install
```

Or install it yourself as:

```
$ gem install durable-llm
```

## Usage

Here's a basic example of how to use Durable-LLM:

```ruby
require 'durable-llm'

# Simple text completion
client = Durable::Llm.new(:openai, api_key: 'your-api-key')
response = client.quick_complete('Hello, how are you?')
puts response

# Full completion with messages
response = client.completion(
  model: 'gpt-3.5-turbo',
  messages: [{ role: 'user', content: 'Hello, how are you?' }]
)
puts response.choices.first.message.content

# Chat completion (alias for completion)
response = client.chat(
  model: 'gpt-3.5-turbo',
  messages: [{ role: 'user', content: 'Hello, how are you?' }]
)

# Streaming responses
client.stream(model: 'gpt-3.5-turbo', messages: [...]) do |chunk|
  print chunk.choices.first.delta.content
end

# Embeddings (if supported by provider)
response = client.embed(
  model: 'text-embedding-ada-002',
  input: 'Hello world'
)
```

## Features

- Unified interface for multiple LLM providers
- Consistent input/output format across different models
- Simple `quick_complete()` method for text completion
- Full `completion()` and `chat()` methods for complex interactions
- `embed()` method for text embeddings
- `stream()` method for real-time streaming responses
- Comprehensive error handling and retries
- Customizable timeout and request options
- Environment variable configuration support

## Supported Providers

- OpenAI
- Anthropic
- Google (Gemini)
- Cohere
- Mistral AI
- Groq
- Fireworks AI
- Together AI
- DeepSeek
- OpenRouter
- Perplexity
- xAI
- Azure OpenAI
- Hugging Face 

## Configuration

Configure Durable-LLM globally using environment variables or programmatically:

```ruby
# Environment variables (recommended)
# export DLLM__OPENAI__API_KEY=your-openai-key
# export DLLM__ANTHROPIC__API_KEY=your-anthropic-key

# Or configure programmatically
Durable::Llm.configure do |config|
  config.default_provider   = :openai
  config.openai.api_key     = 'your-openai-api-key'
  config.anthropic.api_key  = 'your-anthropic-api-key'
  # Add other provider configurations as needed
end

# Create clients with automatic configuration
client = Durable::Llm.new(:openai)  # Uses configured API key
client = Durable::Llm.new(:anthropic, model: 'claude-3-sonnet-20240229')
```

## Error Handling

Durable-LLM provides a unified error handling system:

```ruby
begin
  response = client.completion(model: 'gpt-3.5-turbo', messages: [...])
rescue Durable::Llm::APIError => e
  puts "API Error: #{e.message}"
rescue Durable::Llm::RateLimitError => e
  puts "Rate Limit Exceeded: #{e.message}"
rescue Durable::Llm::AuthenticationError => e
  puts "Authentication Failed: #{e.message}"
end
```

## Acknowledgements

Thank you to the lite-llm and llm.datasette.io projects for their hard work, which was invaluable to this project. The dllm command line tool is patterned after the llm tool, though not as full-featured (yet).

The streaming jsonl code is from the ruby-openai repo; many thanks for their hard work.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/durableprogramming/durable-llm.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
