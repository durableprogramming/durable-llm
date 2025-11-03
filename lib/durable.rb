# frozen_string_literal: true

# Main entry point for the Durable gem.
#
# This module provides a namespace for Durable Programming LLC's Ruby gems.
# It uses autoloading for efficient memory usage and lazy loading of components.
#
# Currently, it provides access to the LLM functionality through the Llm submodule.
#
# @example Basic usage
#   require 'durable'
#
#   # Access LLM functionality
#   Durable::Llm.configure do |config|
#     config.openai.api_key = 'your-key'
#   end
#
#   client = Durable::Llm.new(:openai)
#   response = client.complete('Hello!')
#
# @see Durable::Llm

# Namespace module for Durable Programming LLC's Ruby gems.
#
# This module serves as the root namespace for all Durable gems, providing
# autoloaded access to various components and functionality.
module Durable
  # Autoload the Llm module for lazy loading
  autoload :Llm, 'durable/llm'
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
