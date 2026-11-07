#!/usr/bin/env ruby
# frozen_string_literal: true

# Pressure / load bench for ActiveVersion hot paths:
# - context merge + JSON encode + ActiveRecord::Connection#quote (SET LOCAL payload shape)
# - audit-writer style context stringify/merge (representative loop)
# - SQLBuilder-style context merge for batch audit values (no DB)
# - Query.audits / translations / revisions relation construction (see pressure_probe.rb)
#
# Usage:
#   bundle exec ruby benchmarks/load.rb
#   SCENARIO=matrix bundle exec ruby benchmarks/load.rb
#   CONTEXT_ITERS=80000 AUDIT_ITERS=80000 SQLBUILDER_ITERS=60000 QUERY_ITERS=20000 bundle exec ruby benchmarks/load.rb
#
# Env:
#   SCENARIO=matrix|context|audit|sql_builder|query|single|fiber (default matrix)
#   CONTEXT_ITERS, AUDIT_ITERS, SQLBUILDER_ITERS, QUERY_ITERS — loop counts
#   CONTEXT_KEYS — extra keys in synthetic context hashes
#   MERGE_REPS — inner repetitions for pressure step multiplier
#   BENCH_FIBER_N — store/context ops for fiber scenario (default 3000)
#   BENCH_FIBER_COUNT — concurrent Fibers per wave (default 8)
#   AUDIT_BENCH_LEGACY=1 — audit step uses old `dup.merge` for every row (baseline the pre-change writer)
#   TARGET_FACTOR — baseline-derived ceiling factor (default 0.85)
#   PRESSURE_TARGET_SLACK — extra multiplier for hotter step wall/cpu (default 1.32; micro-bench variance)
#   PRESSURE_POLYRUN_LIB — optional override for sibling polyrun.rb lib/

require_relative "pressure_probe"

BENCH_GEM_ROOT = File.expand_path("..", __dir__).freeze
lib = ENV["PRESSURE_POLYRUN_LIB"] || File.expand_path("../polyrun.rb/lib", BENCH_GEM_ROOT)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

begin
  require "polyrun/benchmark/pressure"
rescue LoadError
  require File.join(lib, "polyrun", "benchmark", "pressure")
end

module ActiveVersion
  module Bench
    module Load
      module_function

      def run!
        factor = ENV.fetch("TARGET_FACTOR", Polyrun::Benchmark::Pressure::DEFAULT_TARGET_FACTOR.to_s).to_f
        scenario = ENV.fetch("SCENARIO", "matrix")
        @context_iters = env_int("CONTEXT_ITERS", 60_000)
        @audit_iters = env_int("AUDIT_ITERS", 60_000)
        @sqlbuilder_iters = env_int("SQLBUILDER_ITERS", 45_000)
        @query_iters = env_int("QUERY_ITERS", 15_000)
        @context_keys = env_int("CONTEXT_KEYS", 8)
        @merge_reps = env_int("MERGE_REPS", 2)

        ActiveVersion::Bench::PressureProbe.setup_database!

        puts "ActiveVersion pressure load scenario=#{scenario} context_iters=#{@context_iters} audit_iters=#{@audit_iters} sqlbuilder_iters=#{@sqlbuilder_iters} query_iters=#{@query_iters} keys=#{@context_keys}"

        results =
          case scenario
          when "matrix" then run_matrix!(factor)
          when "context" then [run_context!(@context_iters, label: "context_encode_quote")]
          when "audit" then [run_audit_merge!(@audit_iters, label: "audit_stringify_merge")]
          when "sql_builder" then [run_sql_builder_merge!(@sqlbuilder_iters, label: "sql_builder_context_merge")]
          when "query" then [run_query_helpers!(@query_iters, label: "query_helpers_relations")]
          when "single" then [run_context!(@context_iters, label: "single_context")]
          when "fiber" then run_fiber_matrix!
          else
            raise "Unknown SCENARIO=#{scenario.inspect}"
          end

        path = Polyrun::Benchmark::Pressure.write_results!(results, repository_root: BENCH_GEM_ROOT, name: "load")
        results.each { |row| puts row["report"] }
        puts "wrote #{path}"
        exit((results.any? { |row| row["pass"] == false }) ? 1 : 0)
      end

      def run_fiber_matrix!
        fiber_n = env_int("BENCH_FIBER_N", 3000)
        fiber_count = env_int("BENCH_FIBER_COUNT", 8)
        puts "ActiveVersion fiber bench fiber_n=#{fiber_n} fiber_count=#{fiber_count}"

        [
          measure_fiber_sequential!("baseline_fiber_sequential", fiber_n),
          measure_concurrent_fibers!("baseline_fiber_concurrent", fiber_n, fiber_count: fiber_count, scope: :fiber),
          measure_concurrent_fibers!("baseline_thread_concurrent_fibers", fiber_n, fiber_count: fiber_count, scope: :thread)
        ]
      end

      def with_execution_scope(scope)
        previous = ActiveVersion.config.execution_scope
        ActiveVersion.config.execution_scope = scope
        yield
      ensure
        ActiveVersion.config.execution_scope = previous
        ActiveVersion.clear_context!
      end

      def measure_fiber_sequential!(label, ops)
        with_execution_scope(:fiber) do
          Polyrun::Benchmark::Pressure.measure(
            label: label,
            ops: ops,
            extras: {"execution_scope" => "fiber"}
          ) do
            ops.times do |i|
              ActiveVersion.with_context!(request_id: "seq-#{i}", actor: "bench")
              ActiveVersion.store_set(:active_version_bench_depth, i)
              ActiveVersion.context
              ActiveVersion.clear_context!
            end
          end
        end
      end

      def measure_concurrent_fibers!(label, ops, fiber_count:, scope:)
        with_execution_scope(scope) do
          Polyrun::Benchmark::Pressure.measure(
            label: label,
            ops: ops,
            extras: {"execution_scope" => scope.to_s, "fiber_count" => fiber_count}
          ) do
            i = 0
            while i < ops
              batch = [fiber_count, ops - i].min
              fibers = batch.times.map do |f|
                idx = i + f
                Fiber.new do
                  ActiveVersion.with_context!(request_id: "req-#{idx}", fiber_id: f)
                  ActiveVersion.store_set(:active_version_bench_depth, idx)
                  Fiber.yield
                  ActiveVersion.context
                  ActiveVersion.clear_context!
                end
              end
              fibers.each(&:resume)
              fibers.each(&:resume)
              i += batch
            end
          end
        end
      end

      def run_matrix!(factor)
        baseline = run_context!(@context_iters, label: "baseline_context_encode_quote")
        base_targets = Polyrun::Benchmark::Pressure.targets_from(baseline["metrics"], factor: factor)

        hotter_iters = (@context_iters * 1.5).ceil
        load_ratio = hotter_iters.to_f / @context_iters
        slack = ENV.fetch("PRESSURE_TARGET_SLACK", "1.32").to_f
        targets = scale_targets_for_load(base_targets, load_ratio * slack)
        # Heap/RSS deltas are too noisy in micro-benches; enforce wall/cpu only.
        targets = targets.slice("wall_s", "cpu_s")

        pressure = run_context!(
          hotter_iters,
          label: "pressure_context_#{hotter_iters}x#{@context_keys}",
          targets: targets
        )

        audit = run_audit_merge!(@audit_iters, label: "audit_stringify_merge")
        sql_b = run_sql_builder_merge!(@sqlbuilder_iters, label: "sql_builder_context_merge")
        query = run_query_helpers!(@query_iters, label: "query_helpers_relations")

        [baseline, pressure, audit, sql_b, query]
      end

      def run_context!(iters, label:, targets: nil)
        conn = ActiveRecord::Base.connection
        ops = iters * @merge_reps

        Polyrun::Benchmark::Pressure.measure(
          label: label,
          ops: ops,
          extras: {"targets" => targets}
        ) do
          ActiveVersion::Bench::PressureProbe.context_encode_quote_loop(
            conn,
            iters: iters,
            merge_reps: @merge_reps,
            context_keys: @context_keys
          )
        end
      end

      def run_audit_merge!(iters, label:, targets: nil)
        legacy = ENV["AUDIT_BENCH_LEGACY"] == "1"
        Polyrun::Benchmark::Pressure.measure(label: label, ops: iters, extras: {"targets" => targets}) do
          ActiveVersion::Bench::PressureProbe.audit_merge_loop(iters, legacy: legacy)
        end
      end

      def run_sql_builder_merge!(iters, label:, targets: nil)
        Polyrun::Benchmark::Pressure.measure(label: label, ops: iters, extras: {"targets" => targets}) do
          ActiveVersion::Bench::PressureProbe.sql_builder_context_merge_loop(iters)
        end
      end

      def run_query_helpers!(iters, label:, targets: nil)
        ops = iters * 3
        Polyrun::Benchmark::Pressure.measure(label: label, ops: ops, extras: {"targets" => targets}) do
          ActiveVersion::Bench::PressureProbe.query_helpers_loop(iters)
        end
      end

      # Scale baseline 0.85 ceilings by expected work ratio (hotter_iters / baseline_iters).
      # Raw per-op scaling fails when the inner loop dominates (wall ~= k * iters).
      def scale_targets_for_load(targets, load_ratio)
        targets.transform_values { |v| v.nil? ? nil : v * load_ratio }
      end

      def env_int(name, default)
        Integer(ENV.fetch(name, default.to_s))
      end
    end
  end
end

ActiveVersion::Bench::Load.run! if $PROGRAM_NAME == __FILE__
