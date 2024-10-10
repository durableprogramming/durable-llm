# Configuring Durable-LLM

## Introduction

Durable-LLM supports multiple LLM providers and can be configured using environment variables or a configuration block. This document outlines the various configuration options available.

## General Configuration

You can configure Durable-LLM using a configuration block:

```ruby
Durable::Llm.configure do |config|
  # Configuration options go here
end
```

## Provider-specific Configuration

### OpenAI

To configure the OpenAI provider, you can set the following environment variables:

- `OPENAI_API_KEY`: Your OpenAI API key
- `OPENAI_ORGANIZATION`: (Optional) Your OpenAI organization ID

Alternatively, you can configure it in the configuration block:

```ruby
Durable::Llm.configure do |config|
  config.openai.api_key = 'your-api-key'
  config.openai.organization = 'your-organization-id' # Optional
end
```

### Anthropic

To configure the Anthropic provider, you can set the following environment variable:

- `ANTHROPIC_API_KEY`: Your Anthropic API key

Alternatively, you can configure it in the configuration block:

```ruby
Durable::Llm.configure do |config|
  config.anthropic.api_key = 'your-api-key'
end
```

### Hugging Face

To configure the Hugging Face provider, you can set the following environment variable:

- `HUGGINGFACE_API_KEY`: Your Hugging Face API key

Alternatively, you can configure it in the configuration block:

```ruby
Durable::Llm.configure do |config|
  config.huggingface.api_key = 'your-api-key'
end
```

### Groq

To configure the Groq provider, you can set the following environment variable:

- `GROQ_API_KEY`: Your Groq API key

Alternatively, you can configure it in the configuration block:

```ruby
Durable::Llm.configure do |config|
  config.groq.api_key = 'your-api-key'
end
```

## Using Environment Variables

You can also use environment variables configure any provider. The format is:

```
DLLM__PROVIDER__SETTING
```

For example:

```
DLLM__OPENAI__API_KEY=your-openai-api-key
DLLM__ANTHROPIC__API_KEY=your-anthropic-api-key
```

## Loading Configuration from Datasette

Durable-LLM can load configuration from a io.datasette.llm configuration file located at `~/.config/io.datasette.llm/keys.json`. If this file exists, it will be parsed and used to set API keys for the supported providers.

## Default Provider

You can set a default provider in the configuration:

```ruby
Durable::Llm.configure do |config|
  config.default_provider = 'openai'
end
```

The default provider is set to 'openai' if not specified.

## Supported Models

Each provider supports a set of models. You can get the list of supported models for a provider using the `models` method:

```ruby
Durable::Llm::Providers::OpenAI.models
Durable::Llm::Providers::Anthropic.models
Durable::Llm::Providers::Huggingface.models
Durable::Llm::Providers::Groq.models
```

Note that some services (Anthropic, for example) don't offer a models endpoint, so they are hardcoded; others (Huggingface) have a inordinately long list, so also have a hardcoded list, at least for now.

## Streaming Support

Some providers support streaming responses. You can check if a provider supports streaming:

```ruby
Durable::Llm::Providers::OpenAI.stream?
```

## Conclusion

By properly configuring Durable-LLM, you can easily switch between different LLM providers and models in your application. Remember to keep your API keys secure and never commit them to version control.

