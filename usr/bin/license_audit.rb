#!/usr/bin/env ruby

require "bundler"
require "pathname"
require "rubygems"

ROOT = Pathname(__dir__).join("../..").expand_path
MANIFEST = ROOT.join("docs/THIRD_PARTY_LICENSE_MANIFEST.tsv")

def locked_specs_for(gemfile_path)
  gemfile = Pathname(gemfile_path)
  lockfile = gemfile.dirname.join("Gemfile.lock")
  raise "Missing lockfile: #{lockfile}" unless lockfile.exist?

  Bundler::LockfileParser.new(lockfile.read).specs.sort_by(&:name)
end

def licenses_from_project_gemspec(gem_name)
  gemspec_path = ROOT.glob("*.gemspec").find { |path| File.basename(path, ".gemspec") == gem_name }
  return [] unless gemspec_path

  Gem::Specification.load(gemspec_path.to_s).licenses
end

def licenses_for(gem_name, version)
  version_string = version.to_s

  begin
    licenses = Gem::Specification.find_by_name(gem_name, version_string).licenses
    return licenses if licenses&.any?
  rescue Gem::MissingSpecError
  end

  project_licenses = licenses_from_project_gemspec(gem_name)
  return project_licenses if project_licenses&.any?

  spec_fetcher = (@spec_fetcher ||= Gem::SpecFetcher.new)
  dependency = Gem::Dependency.new(gem_name, version_string)
  remote_spec = spec_fetcher.spec_for_dependency(dependency).first&.first&.first
  remote_spec&.licenses || []
end

def report_progress(bundle_label, index, total, gem_name)
  message = "License audit: #{bundle_label} #{index}/#{total} #{gem_name}"
  if $stderr.tty?
    $stderr.print("\r\e[2K#{message}")
    $stderr.flush
  else
    $stderr.puts(message)
  end
end

def finish_progress
  $stderr.puts if $stderr.tty?
end

def rows_for(bundle_label, gemfile_path)
  specs = locked_specs_for(gemfile_path)
  total = specs.size

  specs.map.with_index(1) do |spec, index|
    report_progress(bundle_label, index, total, spec.name)
    [bundle_label, spec.name, spec.version.to_s, licenses_for(spec.name, spec.version).join("|")]
  end
end

rows = [["bundle", "gem", "version", "licenses"]]
rows.concat(rows_for("root", ROOT.join("Gemfile")))

demo_gemfile = ROOT.join("examples/rails_demo/Gemfile")
rows.concat(rows_for("rails_demo", demo_gemfile)) if demo_gemfile.exist?

finish_progress

MANIFEST.dirname.mkpath
MANIFEST.write(rows.map { |row| row.join("\t") }.join("\n") + "\n")
puts "Wrote #{MANIFEST}"
