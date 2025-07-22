# This file serves as the main entry point for the Durable gem, providing a namespace module and requiring the core LLM functionality. The Durable module acts as a container for the gem's components and can be extended in the future to include additional Durable-related features beyond the current LLM capabilities.

require 'durable/llm'

module Durable
  # This module serves as a namespace for the Durable gem.
  # It currently only requires the Llm module, but can be expanded
  # in the future to include other Durable-related functionality.
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.