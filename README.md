# Durable-LLM

Durable-LLM is a Ruby gem providing a unified interface for interacting with multiple Large Language Model APIs. It simplifies the integration of AI capabilities into Ruby applications by offering a consistent way to access various LLM providers.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'durable-llm'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install durable-llm
```

## Quick Start

### Simple Completion

```ruby
require 'durable-llm'

# Quick and simple - just provide an API key and model
client = Durable::Llm.new(:openai, api_key: 'your-api-key', model: 'gpt-4')
response = client.complete('What is the capital of France?')
puts response # => "The capital of France is Paris."
```

### Using Global Configuration

```ruby
require 'durable-llm'

# Configure once, use everywhere
Durable::Llm.configure do |config|
  config.openai.api_key = 'your-openai-api-key'
  config.anthropic.api_key = 'your-anthropic-api-key'
end

# Create clients without passing API keys
client = Durable::Llm.new(:openai, model: 'gpt-4')
response = client.complete('Hello, world!')
puts response
```

### Chat Conversations

```ruby
client = Durable::Llm.new(:openai, model: 'gpt-4')

response = client.chat(
  messages: [
    { role: 'system', content: 'You are a helpful assistant.' },
    { role: 'user', content: 'What is Ruby?' }
  ]
)

puts response.choices.first.message.content
```

### Streaming Responses

```ruby
client = Durable::Llm.new(:openai, model: 'gpt-4')

client.stream(messages: [{ role: 'user', content: 'Count to 10' }]) do |chunk|
  content = chunk.dig('choices', 0, 'delta', 'content')
  print content if content
end
puts # New line after streaming
```

### Embeddings

```ruby
client = Durable::Llm.new(:openai)

response = client.embed(
  model: 'text-embedding-ada-002',
  input: 'Ruby is a dynamic programming language'
)

embedding = response.data.first.embedding
puts "Vector dimensions: #{embedding.length}"
```

## Features

- **Unified Interface**: Consistent API across 15+ LLM providers
- **Multiple Providers**: OpenAI, Anthropic, Google, Cohere, Mistral, and more
- **Streaming Support**: Real-time streaming responses
- **Embeddings**: Generate text embeddings for semantic search
- **Configuration Management**: Flexible configuration via environment variables or code
- **Error Handling**: Comprehensive error types for precise handling
- **CLI Tool**: Command-line interface for quick testing and exploration

## Supported Providers

Durable-LLM supports the following LLM providers:

- **OpenAI** - GPT-3.5, GPT-4, GPT-4 Turbo, and embeddings
- **Anthropic** - Claude 3 (Opus, Sonnet, Haiku)
- **Google** - Gemini models
- **Cohere** - Command and embedding models
- **Mistral AI** - Mistral models
- **Groq** - Fast inference with various models
- **Fireworks AI** - High-performance model serving
- **Together AI** - Open-source model hosting
- **DeepSeek** - DeepSeek models
- **OpenRouter** - Access to multiple models via single API
- **Perplexity** - Perplexity models
- **xAI** - Grok models
- **Azure OpenAI** - Microsoft Azure-hosted OpenAI models
- **HuggingFace** - Open-source models via Hugging Face
- **OpenCode** - Code-specialized models

## Configuration

### Environment Variables

Set API keys using environment variables with the `DLLM__` prefix:

```bash
export DLLM__OPENAI__API_KEY=your-openai-key
export DLLM__ANTHROPIC__API_KEY=your-anthropic-key
export DLLM__GOOGLE__API_KEY=your-google-key
```

### Programmatic Configuration

Configure API keys and settings in your code:

```ruby
Durable::Llm.configure do |config|
  config.openai.api_key = 'sk-...'
  config.anthropic.api_key = 'sk-ant-...'
  config.google.api_key = 'your-google-key'
  config.cohere.api_key = 'your-cohere-key'
end
```

### Per-Client Configuration

Pass configuration directly when creating a client:

```ruby
client = Durable::Llm.new(
  :openai,
  api_key: 'your-api-key',
  model: 'gpt-4',
  timeout: 120
)
```

## API Reference

### Client Methods

#### `new(provider, options = {})`

Creates a new LLM client for the specified provider.

**Parameters:**
- `provider` (Symbol) - Provider name (`:openai`, `:anthropic`, etc.)
- `options` (Hash) - Configuration options
  - `:model` - Default model to use
  - `:api_key` - API key for authentication
  - Other provider-specific options

**Returns:** `Durable::Llm::Client` instance

#### `complete(text, opts = {})`

Performs a simple text completion with minimal configuration.

**Parameters:**
- `text` (String) - Input text to complete
- `opts` (Hash) - Additional options (reserved for future use)

**Returns:** String with the completion text

**Note:** The older method name `quick_complete` is still supported as an alias for backward compatibility.

**Example:**
```ruby
client = Durable::Llm.new(:openai, model: 'gpt-4')
response = client.complete('Explain quantum computing in one sentence')
puts response
```

#### `completion(params = {})`

Performs a completion request with full control over parameters.

**Parameters:**
- `params` (Hash) - Completion parameters
  - `:model` - Model to use (overrides default)
  - `:messages` - Array of message hashes with `:role` and `:content`
  - `:temperature` - Sampling temperature (0.0-2.0)
  - `:max_tokens` - Maximum tokens to generate
  - Other provider-specific parameters

**Returns:** Response object with completion data

**Example:**
```ruby
response = client.completion(
  messages: [
    { role: 'system', content: 'You are a helpful coding assistant.' },
    { role: 'user', content: 'Write a Ruby method to reverse a string' }
  ],
  temperature: 0.7,
  max_tokens: 500
)
```

#### `chat(params = {})`

Alias for `completion` - performs a chat completion request.

#### `stream(params = {}, &block)`

Performs a streaming completion request, yielding chunks as they arrive.

**Parameters:**
- `params` (Hash) - Same as `completion`
- `block` - Block to process each chunk

**Example:**
```ruby
client.stream(messages: [{ role: 'user', content: 'Write a story' }]) do |chunk|
  content = chunk.dig('choices', 0, 'delta', 'content')
  print content if content
end
```

#### `embed(params = {})`

Generates embeddings for the given text.

**Parameters:**
- `params` (Hash) - Embedding parameters
  - `:model` - Embedding model to use
  - `:input` - Text or array of texts to embed

**Returns:** Response object with embedding vectors

**Example:**
```ruby
response = client.embed(
  model: 'text-embedding-ada-002',
  input: ['First text', 'Second text']
)

embeddings = response.data.map(&:embedding)
```

## Error Handling

Durable-LLM provides a comprehensive hierarchy of error classes for precise error handling:

```ruby
begin
  response = client.completion(messages: [...])
rescue Durable::Llm::AuthenticationError => e
  puts "Invalid API key: #{e.message}"
rescue Durable::Llm::RateLimitError => e
  puts "Rate limit exceeded, try again later: #{e.message}"
rescue Durable::Llm::InvalidRequestError => e
  puts "Invalid request parameters: #{e.message}"
rescue Durable::Llm::ModelNotFoundError => e
  puts "Model not found: #{e.message}"
rescue Durable::Llm::TimeoutError => e
  puts "Request timed out: #{e.message}"
rescue Durable::Llm::ServerError => e
  puts "Provider server error: #{e.message}"
rescue Durable::Llm::NetworkError => e
  puts "Network connectivity issue: #{e.message}"
rescue Durable::Llm::Error => e
  puts "General LLM error: #{e.message}"
end
```

### Error Types

- `Durable::Llm::Error` - Base error class for all LLM errors
- `Durable::Llm::APIError` - Generic API error
- `Durable::Llm::AuthenticationError` - Invalid or missing API key
- `Durable::Llm::RateLimitError` - Rate limit exceeded
- `Durable::Llm::InvalidRequestError` - Invalid request parameters
- `Durable::Llm::ModelNotFoundError` - Requested model not found
- `Durable::Llm::ResourceNotFoundError` - Resource not found
- `Durable::Llm::TimeoutError` - Request timeout
- `Durable::Llm::ServerError` - Provider server error
- `Durable::Llm::InsufficientQuotaError` - Insufficient account quota
- `Durable::Llm::InvalidResponseError` - Malformed response
- `Durable::Llm::NetworkError` - Network connectivity issue
- `Durable::Llm::StreamingError` - Streaming-specific error
- `Durable::Llm::ConfigurationError` - Configuration problem
- `Durable::Llm::UnsupportedProviderError` - Provider not supported

## CLI Tool

Durable-LLM includes a command-line tool (`dllm`) for quick interactions:

```bash
# One-shot completion
$ dllm prompt "What is Ruby?" -m gpt-3.5-turbo

# Interactive chat
$ dllm chat -m gpt-4

# List available models
$ dllm models

# Manage conversations
$ dllm conversations
```

## Advanced Usage

### Fluent API with Method Chaining

```ruby
client = Durable::Llm.new(:openai, model: 'gpt-3.5-turbo')

# Chain configuration methods for cleaner code
result = client
  .with_model('gpt-4')
  .with_temperature(0.7)
  .with_max_tokens(500)
  .complete('Write a haiku about Ruby')

puts result
```

### Response Helpers

Extract information from responses easily:

```ruby
require 'durable-llm'

response = client.chat(messages: [{ role: 'user', content: 'Hello!' }])

# Extract content directly
content = Durable::Llm::ResponseHelpers.extract_content(response)

# Get token usage
tokens = Durable::Llm::ResponseHelpers.token_usage(response)
puts "Used #{tokens[:total_tokens]} tokens"

# Check why the response finished
reason = Durable::Llm::ResponseHelpers.finish_reason(response)
puts "Finished: #{reason}"

# Estimate cost
cost = Durable::Llm::ResponseHelpers.estimate_cost(response)
puts "Estimated cost: $#{cost}"
```

### Provider Utilities

Discover and compare providers:

```ruby
# Find which provider supports a model
provider = Durable::Llm::ProviderUtilities.provider_for_model('gpt-4')
# => :openai

# List all available providers
providers = Durable::Llm::ProviderUtilities.available_providers
# => [:openai, :anthropic, :google, ...]

# Check provider capabilities
Durable::Llm::ProviderUtilities.supports_capability?(:openai, :streaming)
# => true

# Get all provider info
info = Durable::Llm::ProviderUtilities.all_provider_info
```

### Fallback Chains for Resilience

Create robust systems with automatic fallback:

```ruby
# Execute with fallback providers
result = Durable::Llm::ProviderUtilities.complete_with_fallback(
  'What is Ruby?',
  providers: [:openai, :anthropic, :google],
  model_map: {
    openai: 'gpt-4',
    anthropic: 'claude-3-opus-20240229',
    google: 'gemini-pro'
  }
)

puts result
```

### Global Convenience Functions

Quick access without module qualification:

```ruby
require 'durable-llm'

# Quick client creation
client = DLLM(:openai, model: 'gpt-4')

# One-liner completions
result = LlmComplete('Hello!', model: 'gpt-4')

# Configure globally
LlmConfigure do |config|
  config.openai.api_key = 'sk-...'
end

# List models
models = LlmModels(:openai)
```

### Custom Timeout

```ruby
client = Durable::Llm.new(
  :openai,
  model: 'gpt-4',
  timeout: 120  # 2 minutes
)
```

### Provider-Specific Options

Some providers support additional options:

```ruby
# Azure OpenAI with custom endpoint
client = Durable::Llm.new(
  :azureopenai,
  api_key: 'your-key',
  endpoint: 'https://your-resource.openai.azure.com',
  api_version: '2024-02-15-preview'
)
```

### Model Discovery

```ruby
# Get list of available models for a provider
models = Durable::Llm.models(:openai)
puts models.inspect

# Or using provider utilities
models = Durable::Llm::ProviderUtilities.models_for_provider(:anthropic)
```

### Cloning Clients with Different Settings

```ruby
base_client = Durable::Llm.new(:openai, model: 'gpt-3.5-turbo')

# Create variant clients for different use cases
fast_client = base_client.clone_with(model: 'gpt-3.5-turbo')
powerful_client = base_client.clone_with(model: 'gpt-4')

# Use them for different tasks
summary = fast_client.complete('Summarize: ...')
analysis = powerful_client.complete('Analyze in depth: ...')
```

## Practical Examples

### Building a Simple Chatbot

```ruby
require 'durable-llm'

client = Durable::Llm.new(:openai, model: 'gpt-4')
conversation = [{ role: 'system', content: 'You are a helpful assistant.' }]

loop do
  print "You: "
  user_input = gets.chomp
  break if user_input.downcase == 'exit'

  conversation << { role: 'user', content: user_input }

  response = client.chat(messages: conversation)
  assistant_message = Durable::Llm::ResponseHelpers.extract_content(response)

  conversation << { role: 'assistant', content: assistant_message }
  puts "Assistant: #{assistant_message}"
end
```

### Multi-Provider Text Analysis

```ruby
require 'durable-llm'

text = "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity."

providers = {
  openai: 'gpt-4',
  anthropic: 'claude-3-opus-20240229',
  google: 'gemini-pro'
}

results = providers.map do |provider, model|
  client = Durable::Llm.new(provider, model: model)
  response = client.complete("Summarize this in 5 words: #{text}")

  { provider: provider, model: model, summary: response }
end

results.each do |result|
  puts "#{result[:provider]} (#{result[:model]}): #{result[:summary]}"
end
```

### Batch Processing with Progress Tracking

```ruby
require 'durable-llm'

client = Durable::Llm.new(:openai, model: 'gpt-3.5-turbo')

texts = [
  "Ruby is elegant",
  "Python is versatile",
  "JavaScript is ubiquitous"
]

results = texts.map.with_index do |text, i|
  puts "Processing #{i + 1}/#{texts.length}..."

  response = client.chat(
    messages: [{ role: 'user', content: "Expand on: #{text}" }]
  )

  content = Durable::Llm::ResponseHelpers.extract_content(response)
  tokens = Durable::Llm::ResponseHelpers.token_usage(response)

  {
    input: text,
    output: content,
    tokens: tokens[:total_tokens]
  }
end

total_tokens = results.sum { |r| r[:tokens] }
puts "\nProcessed #{results.length} texts using #{total_tokens} tokens"
```

### Sentiment Analysis with Error Handling

```ruby
require 'durable-llm'

def analyze_sentiment(text)
  client = Durable::Llm.new(:openai, model: 'gpt-4')

  prompt = <<~PROMPT
    Analyze the sentiment of this text and respond with only one word:
    positive, negative, or neutral.

    Text: #{text}
  PROMPT

  response = client.complete(prompt)
  response.strip.downcase
rescue Durable::Llm::RateLimitError => e
  puts "Rate limited, waiting..."
  sleep 5
  retry
rescue Durable::Llm::APIError => e
  puts "API error: #{e.message}"
  'unknown'
end

texts = [
  "I love this product!",
  "This is terrible.",
  "It's okay, I guess."
]

texts.each do |text|
  sentiment = analyze_sentiment(text)
  puts "\"#{text}\" -> #{sentiment}"
end
```

### Code Generation Assistant

```ruby
require 'durable-llm'

client = Durable::Llm.new(:openai, model: 'gpt-4')

def generate_code(description)
  prompt = <<~PROMPT
    Generate Ruby code for: #{description}

    Provide only the code, no explanations.
  PROMPT

  client
    .with_temperature(0.3)  # Lower temperature for more deterministic code
    .with_max_tokens(500)
    .complete(prompt)
end

# Example usage
code = generate_code("a method that reverses a string")
puts code
```

### Streaming Real-Time Translation

```ruby
require 'durable-llm'

client = Durable::Llm.new(:openai, model: 'gpt-4')

def translate_streaming(text, target_language)
  messages = [{
    role: 'user',
    content: "Translate to #{target_language}: #{text}"
  }]

  print "Translation: "
  client.stream(messages: messages) do |chunk|
    content = chunk.dig('choices', 0, 'delta', 'content')
    print content if content
  end
  puts
end

translate_streaming("Hello, how are you?", "Spanish")
translate_streaming("The weather is nice today.", "French")
```

## Acknowledgements

Thank you to the lite-llm and llm.datasette.io projects for their hard work, which was invaluable to this project. The dllm command line tool is patterned after the llm tool, though not as full-featured (yet).

The streaming jsonl code is from the ruby-openai repo; many thanks for their hard work.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/durableprogramming/durable-llm.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
