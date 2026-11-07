# frozen_string_literal: true

# Shared hot-path work unit for ActiveVersion pressure benches (`benchmarks/load.rb`).
# Keeps one implementation of the probe body so calibrate/baseline/stress stay comparable.

require "json"
require "active_record"
require "active_support/json"

_gem_root = File.expand_path("..", __dir__).freeze
$LOAD_PATH.unshift(File.join(_gem_root, "lib")) unless $LOAD_PATH.include?(File.join(_gem_root, "lib"))
require "active_version"

module ActiveVersion
  module Bench
    module PressureProbe
      module_function

      def setup_database!
        ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
        ActiveRecord::Schema.define(version: 1) do
          create_table :bench_load_posts, force: :cascade do |t|
            t.string :title
          end
          create_table :bench_load_audits, force: :cascade do |t|
            t.string :auditable_type
            t.integer :auditable_id
            t.string :action
          end
        end
        stub_models!
        BenchLoadPost.delete_all
        BenchLoadAudit.delete_all
        BenchLoadPost.create!(title: "pressure-probe")
        ActiveVersion.reset_runtime_adapter!
      end

      def stub_models!
        return if defined?(BenchLoadPost) && BenchLoadPost < ActiveRecord::Base

        eval(<<~RUBY, TOPLEVEL_BINDING, __FILE__, __LINE__ + 1)
          class BenchLoadPost < ActiveRecord::Base
            self.table_name = "bench_load_posts"
            def self.audit_class = BenchLoadAudit
            def self.translation_class = nil
            def self.revision_class = nil
          end
          class BenchLoadAudit < ActiveRecord::Base
            self.table_name = "bench_load_audits"
          end
        RUBY
      end

      def context_encode_quote_loop(conn, iters:, merge_reps:, context_keys:)
        persistent, request, block_ctx = sample_context_hashes(context_keys)
        merge_reps.times do
          conn.transaction do
            iters.times do
              merged = persistent.merge(request).merge(block_ctx)
              payload = ActiveVersion.json_encode(merged)
              encoded = conn.quote(payload)
              raise "empty quote" if encoded.nil? || encoded.bytesize < 2
            end
          end
        end
      end

      def sql_builder_context_merge_loop(iters)
        global_context = {("g" * 3) => 1, ("k" * 3) => 2}
        instance_context = {("i" * 3) => 3}
        options_context = {("o" * 3) => 4}
        iters.times do
          context = global_context.merge(instance_context || {})
          context.merge!(options_context || {})
          attrs = {}
          attrs[:audited_context] = context if context.any?
          raise "expected context" unless attrs[:audited_context]
        end
      end

      def query_helpers_loop(iters)
        post = BenchLoadPost.first!
        iters.times do
          ActiveVersion::Query.audits(post)
          ActiveVersion::Query.translations(post)
          ActiveVersion::Query.revisions(post)
        end
      end

      # Full probe: context encode + quote, audit-style merge, sql_builder merge, Query.* relation builds.
      def work_once(
        context_iters:,
        audit_iters:,
        sql_builder_iters:,
        query_iters:,
        context_keys:,
        merge_reps:,
        audit_legacy: false
      )
        conn = ActiveRecord::Base.connection
        context_encode_quote_loop(conn, iters: context_iters, merge_reps: merge_reps, context_keys: context_keys)

        audit_merge_loop(audit_iters, legacy: audit_legacy)
        sql_builder_context_merge_loop(sql_builder_iters)
        query_helpers_loop(query_iters)
      end

      def audit_merge_loop(iters, legacy: false)
        iters.times do |i|
          block_context = {("b" * 4) => "block"}
          persistent_context = {("p" * 4) => "persistent"}
          global_context = persistent_context.stringify_keys.merge(block_context.stringify_keys)

          raw_instance_context = (i.even? ? nil : {("i" * 4) => "inst"})
          instance_context = if raw_instance_context.nil?
            {}
          elsif raw_instance_context.is_a?(Hash)
            raw_instance_context.stringify_keys
          else
            {}
          end

          captured_context = if legacy
            global_context.dup.merge(instance_context)
          elsif instance_context.empty?
            global_context.dup
          else
            global_context.dup.merge!(instance_context)
          end
          raise "bad merge" unless captured_context[("p" * 4)] == "persistent"
        end
      end

      def sample_context_hashes(keys)
        rng = Random.new(42)
        base = {}
        keys.times { |i| base["k#{i}"] = "v#{rng.rand(1000)}" }
        [base, {"req" => "scoped", "n" => rng.rand(9999)}, {"txn" => "local"}]
      end

      def total_ops(context_iters:, audit_iters:, sql_builder_iters:, query_iters:, merge_reps:)
        (context_iters * merge_reps) + audit_iters + sql_builder_iters + (query_iters * 3)
      end
    end
  end
end
