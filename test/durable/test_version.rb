# frozen_string_literal: true

require 'test_helper'
require 'durable/llm/version'

class TestVersion < Minitest::Test
  def test_version_constant
    assert_equal '0.1.4', Durable::Llm::VERSION
    assert_instance_of String, Durable::Llm::VERSION
  end

  def test_version_format
    version = Durable::Llm::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, version, 'Version should follow SemVer format MAJOR.MINOR.PATCH')
  end

  def test_version_parts
    major, minor, patch = Durable::Llm::VERSION.split('.').map(&:to_i)
    assert major >= 0
    assert minor >= 0
    assert patch >= 0
  end

  def test_version_class_parse
    version = Durable::Llm::Version.parse('1.2.3')
    assert_equal 1, version.major
    assert_equal 2, version.minor
    assert_equal 3, version.patch
    assert_nil version.pre_release
    assert_nil version.build_metadata
  end

  def test_version_class_parse_with_pre_release
    version = Durable::Llm::Version.parse('1.2.3-alpha.1')
    assert_equal 1, version.major
    assert_equal 2, version.minor
    assert_equal 3, version.patch
    assert_equal 'alpha.1', version.pre_release
    assert_nil version.build_metadata
  end

  def test_version_class_parse_with_build_metadata
    version = Durable::Llm::Version.parse('1.2.3+build.1')
    assert_equal 1, version.major
    assert_equal 2, version.minor
    assert_equal 3, version.patch
    assert_nil version.pre_release
    assert_equal 'build.1', version.build_metadata
  end

  def test_version_class_parse_full
    version = Durable::Llm::Version.parse('1.2.3-beta.1+build.2')
    assert_equal 1, version.major
    assert_equal 2, version.minor
    assert_equal 3, version.patch
    assert_equal 'beta.1', version.pre_release
    assert_equal 'build.2', version.build_metadata
  end

  def test_version_class_parse_invalid
    assert_raises(ArgumentError) { Durable::Llm::Version.parse('invalid') }
    assert_raises(ArgumentError) { Durable::Llm::Version.parse('1.2') }
    assert_raises(ArgumentError) { Durable::Llm::Version.parse('1.2.3.4') }
  end

  def test_version_class_to_s
    version = Durable::Llm::Version.new(1, 2, 3)
    assert_equal '1.2.3', version.to_s

    version = Durable::Llm::Version.new(1, 2, 3, 'alpha.1')
    assert_equal '1.2.3-alpha.1', version.to_s

    version = Durable::Llm::Version.new(1, 2, 3, nil, 'build.1')
    assert_equal '1.2.3+build.1', version.to_s

    version = Durable::Llm::Version.new(1, 2, 3, 'beta.1', 'build.2')
    assert_equal '1.2.3-beta.1+build.2', version.to_s
  end

  def test_version_class_comparison
    v1 = Durable::Llm::Version.parse('1.0.0')
    v2 = Durable::Llm::Version.parse('1.0.1')
    v3 = Durable::Llm::Version.parse('1.1.0')
    v4 = Durable::Llm::Version.parse('2.0.0')

    assert v1 < v2
    assert v2 < v3
    assert v3 < v4
    assert v1 == Durable::Llm::Version.parse('1.0.0')
  end

  def test_version_class_pre_release?
    assert Durable::Llm::Version.parse('1.0.0-alpha').pre_release?
    refute Durable::Llm::Version.parse('1.0.0').pre_release?
  end

  def test_version_class_current
    current = Durable::Llm::Version.current
    assert_equal Durable::Llm::VERSION, current.to_s
  end

  def test_version_class_parse_self
    version = Durable::Llm::Version.parse('1.0.0')
    assert_same version, Durable::Llm::Version.parse(version)
  end
end
