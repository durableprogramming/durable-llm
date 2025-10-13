# frozen_string_literal: true

# Defines the version constant and Version class for the Durable::Llm gem.

module Durable
  module Llm
    VERSION = '0.1.4'

    # Version class for parsing and comparing semantic versions
    class Version
      include Comparable

      attr_reader :major, :minor, :patch, :pre_release, :build_metadata

      # Parse a version string into components
      #
      # @param version_string [String] The version string to parse
      # @return [Version] A new Version instance
      # @raise [ArgumentError] If the version string is invalid
      def self.parse(version_string)
        return version_string if version_string.is_a?(Version)

        match = version_string.match(/\A(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.-]+))?(?:\+([a-zA-Z0-9.-]+))?\z/)
        raise ArgumentError, "Invalid version format: #{version_string}" unless match

        major, minor, patch, pre_release, build_metadata = match.captures
        new(major.to_i, minor.to_i, patch.to_i, pre_release, build_metadata)
      end

      # Initialize a new Version
      #
      # @param major [Integer] Major version number
      # @param minor [Integer] Minor version number
      # @param patch [Integer] Patch version number
      # @param pre_release [String, nil] Pre-release identifier
      # @param build_metadata [String, nil] Build metadata
      def initialize(major, minor, patch, pre_release = nil, build_metadata = nil)
        @major = major
        @minor = minor
        @patch = patch
        @pre_release = pre_release
        @build_metadata = build_metadata
      end

      # Convert to string representation
      #
      # @return [String] The version as a string
      def to_s
        str = "#{major}.#{minor}.#{patch}"
        str += "-#{pre_release}" if pre_release
        str += "+#{build_metadata}" if build_metadata
        str
      end

      # Compare versions for ordering
      #
      # @param other [Version, String] The version to compare against
      # @return [Integer] -1, 0, or 1
      def <=>(other)
        other = self.class.parse(other) unless other.is_a?(Version)

        [major, minor, patch] <=> [other.major, other.minor, other.patch]
      end

      # Check if this is a pre-release version
      #
      # @return [Boolean] True if this is a pre-release
      def pre_release?
        !pre_release.nil?
      end

      # Get the current gem version
      #
      # @return [Version] The current version of the gem
      def self.current
        parse(VERSION)
      end
    end
  end
end

# Copyright (c) 2025 Durable Programming, LLC. All rights reserved.
