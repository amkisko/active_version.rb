# Fiber isolation review

## Participants

Andrei Makarov (@amkisko)

## Decisions

No new Fiber API. `ActiveVersion.config.execution_scope` already supports `:fiber` (default) and `:thread`. Persistent context, auditing/revision disable depths, and `with_audited_options` go through `store_get` / `store_set`. `RequestStore` (`ActiveSupport::CurrentAttributes`) continues to follow the host Rails isolation level; this review does not add a second gem-level switch for CurrentAttributes.

Add maintainer fiber load series (`SCENARIO=fiber` / `make bench-fiber`) so concurrent Fiber store cost under `:fiber` versus `:thread` stays measurable. Do not mark the existing `:fiber` default as experimental; it already shipped as the production default.

Accept measured baselines (n = 3 samples, `SCENARIO=fiber`, `BENCH_FIBER_N=3000`, `BENCH_FIBER_COUNT=8`, Ruby 4.0.7 arm64-darwin).

## Effects

Fiber-local persistent context and disable depths remain the supported path for Falcon-style / interleaved Fiber hosts. Benchmark harness covers sequential Fiber context writes, concurrent Fibers under `:fiber`, and concurrent Fibers under `:thread` (shared stack comparison).

Median of three host samples (`benchmarks/output/fiber_sample_{1,2,3}.log`):

| Series | median ops/s | median wall (s) | alloc |
| --- | ---: | ---: | ---: |
| `baseline_fiber_sequential` | 782676.8 | 0.0038 | 15100 |
| `baseline_fiber_concurrent` | 263181.0 | 0.0114 | 28179 |
| `baseline_thread_concurrent_fibers` | 297353.6 | 0.0101 | 30794 |

Concurrent Fiber work under default `:fiber` is about **0.89×** the ops/s of the same interleaved Fiber workload under `:thread` (shared store). Isolation cost is acceptable; sequential Fiber context path stays much hotter than concurrent waves.

## Next

- Keep documenting that Rails `config.active_support.isolation_level = :fiber` is still required for CurrentAttributes request fields.
- Re-run `make bench-fiber` when store paths change.

## Source

- `lib/active_version.rb` (`store_get` / `store_set`, `execution_scope`)
- `lib/active_version/configuration.rb`
- `spec/active_version/context_system_spec.rb`
- `spec/active_version/core_helpers_spec.rb`
- `benchmarks/load.rb` (`SCENARIO=fiber`)
- `benchmarks/output/fiber_sample_1.log`
- `benchmarks/output/fiber_sample_2.log`
- `benchmarks/output/fiber_sample_3.log`
