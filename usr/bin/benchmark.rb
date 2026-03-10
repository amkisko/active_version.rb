#!/usr/bin/env ruby
require "fileutils"

class BenchmarkRunner
  def self.run(root_dir = ".")
    new(root_dir).run
  end

  def initialize(root_dir)
    @root_dir = File.expand_path(root_dir)
    @combined_log_file = File.join(@root_dir, "tmp/benchmark.log")
  end

  def run
    FileUtils.mkdir_p(File.dirname(@combined_log_file))
    File.write(@combined_log_file, "")

    env = {
      "BENCHMARK" => "1",
      "SIMPLECOV_DISABLE" => "1"
    }

    iterations = ENV["ACTIVE_VERSION_BENCH_ITERATIONS"] || "5000"
    warmup = ENV["ACTIVE_VERSION_BENCH_WARMUP"] || "200"
    rounds = ENV["ACTIVE_VERSION_BENCH_ROUNDS"] || "5"
    env["ACTIVE_VERSION_BENCH_ITERATIONS"] = iterations
    env["ACTIVE_VERSION_BENCH_WARMUP"] = warmup
    env["ACTIVE_VERSION_BENCH_ROUNDS"] = rounds

    bundle_bin = ENV["BUNDLE_BIN"]
    if bundle_bin.to_s.empty?
      mise_bundle = File.expand_path("~/.local/share/mise/shims/bundle")
      bundle_bin = File.exist?(mise_bundle) ? mise_bundle : "bundle"
    end

    cmd = "#{bundle_bin} exec rspec spec/benchmark --tag benchmark --format documentation"
    puts "Running: #{cmd}"
    puts "Iterations: #{iterations}, Warmup: #{warmup}, Rounds: #{rounds}"
    puts "Databases: sqlite, postgresql"

    overall_ok = true
    %w[sqlite postgresql].each do |db|
      section_log = File.join(@root_dir, "tmp/benchmark_#{db}.log")
      section_header = "\n===== BENCHMARK SECTION: #{db.upcase} =====\n"
      File.write(@combined_log_file, section_header, mode: "a")
      puts section_header

      section_env = env.merge("BENCH_DB" => db)
      section_ok = system(section_env, "bash", "-lc", "cd #{@root_dir} && #{cmd} | tee #{section_log}")
      if section_ok
        if File.exist?(section_log)
          File.write(@combined_log_file, File.read(section_log), mode: "a")
        end
      else
        overall_ok = false
      end
    end

    exit(overall_ok ? 0 : 1)
  end
end

if __FILE__ == $PROGRAM_NAME
  root_dir = ARGV[0] || File.expand_path(File.join(__dir__, "../.."))
  BenchmarkRunner.run(root_dir)
end
