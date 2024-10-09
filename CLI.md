Here's the content for the file CLI.md:

# Durable-LLM Command Line Interface (CLI)

Durable-LLM provides a command-line interface (CLI) for interacting with various Large Language Model providers. This document outlines the available commands and their usage.

## Installation

Ensure you have installed the Durable-LLM gem:

```
gem install durable-llm
```

## Commands

### prompt

Run a single prompt and get a response.

```
dllm prompt [OPTIONS] PROMPT
```

Options:
- `-m, --model MODEL`: Specify the model to use (default: gpt-3.5-turbo)
- `-s, --system SYSTEM_PROMPT`: Set a system prompt
- `-c, --continue`: Continue the previous conversation
- `--cid CONVERSATION_ID`: Continue a specific conversation by ID
- `--no-stream`: Disable streaming of tokens
- `-o, --option KEY:VALUE`: Set model-specific options

Example:
```
dllm prompt -m gpt-4 "What is the capital of France?"
```

### chat

Start an interactive chat session.

```
dllm chat [OPTIONS]
```

Options:
- `-m, --model MODEL`: Specify the model to use (default: gpt-3.5-turbo)
- `-s, --system SYSTEM_PROMPT`: Set a system prompt
- `-c, --continue`: Continue the previous conversation
- `--cid CONVERSATION_ID`: Continue a specific conversation by ID
- `-o, --option KEY:VALUE`: Set model-specific options

Example:
```
dllm chat -m claude-3-opus-20240229
```

### models

List available models.

```
dllm models [OPTIONS]
```

Options:
- `--options`: Show model options

Example:
```
dllm models
```

## Configuration

The CLI uses the same configuration as the Durable-LLM library. You can set up your API keys and other settings using environment variables or a configuration file.

Environment variables:
- `DLLM__OPENAI__API_KEY`: OpenAI API key
- `DLLM__ANTHROPIC__API_KEY`: Anthropic API key
- (Add other provider API keys as needed)

Alternatively, you can use the configuration file located at `~/.config/io.datasette.llm/keys.json` for compatibility with the `llm` tool.

## Examples

1. Run a simple prompt:
   ```
   dllm prompt "Tell me a joke"
   ```

2. Start an interactive chat with a specific model:
   ```
   dllm chat -m gpt-4
   ```

3. List available models:
   ```
   dllm models
   ```

4. Run a prompt with a system message and custom options:
   ```
   dllm prompt -s "You are a helpful assistant" -o temperature:0.7 "Explain quantum computing"
   ```

Remember to set up your API keys before using the CLI. Enjoy using Durable-LLM from the command line!
