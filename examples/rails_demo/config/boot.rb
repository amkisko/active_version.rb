
require_relative "../lib/rails_demo/boot_profile"

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

RailsDemo::BootProfile.measure_phase("require bundler/setup") do
  require "bundler/setup" # Set up gems listed in the Gemfile.
end

RailsDemo::BootProfile.measure_phase("require bootsnap/setup") do
  require "bootsnap/setup" # Speed up boot time by caching expensive operations.
end
