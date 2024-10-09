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

client = Durable::Llm::Client.new(:openai, api_key: 'your-api-key')

response = client.completion(
  model: 'gpt-3.5-turbo',
  messages: [{ role: 'user', content: 'Hello, how are you?' }]
)

puts response.choices.first.message.content

```

## Features

- Unified interface for multiple LLM providers
- Consistent input/output format across different models
- Error handling and retries
- Streaming support
- Customizable timeout and request options

## Supported Providers

- OpenAI
- Anthropic
- Grok
- Huggingface

## Configuration

You can configure Durable-LLM globally or on a per-request basis:

```ruby
Durable::Llm.configure do |config|
  config.default_provider   = :openai
  config.openai.api_key     = 'your-openai-api-key'
  config.anthropic.api_key  = 'your-anthropic-api-key'
  # Add other provider configurations as needed
end
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
end
```

## Acknowledgements

Thank you to the lite-llm and llm.datasette.io projects for their hard work, which was invaluable to this project. The dllm command line tool is patterned after the llm tool, though not as full-featured (yet).

The streaming jsonl code is from the ruby-openai repo; many thanks for their hard work.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/durableprogramming/durable-llm.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
