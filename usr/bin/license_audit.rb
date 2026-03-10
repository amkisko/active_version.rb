#!/usr/bin/env ruby

require "bundler"
require "pathname"

ROOT = Pathname(__dir__).join("../..").expand_path
MANIFEST = ROOT.join("docs/THIRD_PARTY_LICENSE_MANIFEST.tsv")

def specs_for(gemfile_path = nil)
  previous = ENV["BUNDLE_GEMFILE"]
  ENV["BUNDLE_GEMFILE"] = gemfile_path.to_s if gemfile_path
  definition = Bundler::Definition.build(
    gemfile_path ? gemfile_path.to_s : ROOT.join("Gemfile").to_s,
    nil,
    nil
  )
  definition.specs.sort_by(&:name)
ensure
  ENV["BUNDLE_GEMFILE"] = previous
end

rows = []

rows << ["bundle", "gem", "version", "licenses"]
specs_for.each do |spec|
  rows << ["root", spec.name, spec.version.to_s, (spec.licenses || []).join("|")]
end

demo_gemfile = ROOT.join("examples/rails_demo/Gemfile")
specs_for(demo_gemfile).each do |spec|
  rows << ["rails_demo", spec.name, spec.version.to_s, (spec.licenses || []).join("|")]
end

MANIFEST.dirname.mkpath
MANIFEST.write(rows.map { |r| r.join("\t") }.join("\n") + "\n")
puts "Wrote #{MANIFEST}"
