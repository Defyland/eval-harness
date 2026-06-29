# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "eval_harness"
require "fileutils"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"
