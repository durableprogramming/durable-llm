require_relative "lib/durable/llm/version"

Gem::Specification.new do |spec|
  spec.name = "durable-llm"
  spec.version = Durable::Llm::VERSION
  spec.authors = ["Durable Programming Team"]
  spec.email = ["djberube@durableprogramming.com"]

  spec.summary = "A Ruby gem providing access to LLM APIs from various vendors"
  spec.description = "Durable-LLM is a unified interface for interacting with multiple Large Language Model APIs, simplifying integration of AI capabilities into Ruby applications."
  spec.homepage = "https://github.com/durableprogramming/durable-llm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/durableprogramming/durable-llm"
  spec.metadata["changelog_uri"] = "https://github.com/durableprogramming/durable-llm/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "> 1.0"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "highline", "~> 3.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "mocha", "~> 2.1"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "vcr", "~> 6.0"
end
