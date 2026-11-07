# Pressure optimizations and C-extension probe

## Participants

Andrei Makarov (@amkisko)

## Scope

`active_version.rb` after the pressure-cooker episode: remove `AV_PRESSURE_BUILD` flags from `lib/`, keep permanent JSON/audit/query optimizations, confirm no custom C is warranted.

Host for cited numbers: Ruby 4.0.x, arm64-darwin. Host-relative, not SLOs.

## Decision: C extension

**Ship custom C extension: no.**

| Probe | Ruby median | C / alternate | Why not ship |
| --- | ---: | --- | --- |
| Context JSON 50k encodes | `JSON.generate` **0.97 µs**/call | no custom C | Already on `json` gem C. |
| Same workload | `ActiveSupport::JSON.encode` **~1.48 µs**/call | ~**1.52×** slower than `JSON.generate` | Prefer `JSON.generate`, not a new extension. |
| Same workload | `JSON.fast_generate` ~**1.21×** vs `JSON.generate` here | — | Keep `JSON.generate` as `ActiveVersion.json_encode`. |

## When to try C extensions again

Retry custom C only when measurement shows the hot path is (1) a large enough share of total time and (2) a tight loop over primitives that `json` does not already cover.

### Try again when

- A new hot path is linear over bytes/ints with a rare Ruby↔C boundary, not another JSON encode wrapper.
- Custom C is a full semantic substitute and beats `JSON.generate` end-to-end by clearly above ~20% median wall (n ≥ 3).
- Profile shows roughly ≥30–40% of time in one tight non-`json` function before writing `ext/`.

### Do not retry when

- The path already sits on the `json` gem C encoder (`ActiveVersion.json_encode`).
- The bottleneck is ORM, SQL, GC, or audit row shape, not encode CPU.
- Platform/ABI/maintenance cost exceeds the measured gain.

### Gate before shipping

1. Load measure: named primary series dominates at L1.
2. Profile: one tight function outside `json` owns a large fraction of time.
3. Throwaway C probe with the same semantics → only then add `ext/` if the full probe improves enough and tests stay green.

Short form: retry C for “new primitive loops”; skip C for “JSON and ActiveRecord work.”

## Permanent Ruby optimizations (flags removed)

| Optimization | Before → after (cited runs) | Diff |
| --- | --- | --- |
| Audit empty instance context: `dup` instead of `dup.merge({})` | audit micro alloc ~**780k** → ~**630k–660k** | ~**−15% to −19%** objects |
| `ActiveVersion.json_encode` → `JSON.generate` on former AS/JSON forks | AS encode ~**1.48 µs** vs `JSON.generate` ~**0.97 µs**/call | ~**−36%** encode wall vs AS wrapper |
| `Query#column_for_cached` | always on | cache hit path for column lookup |
| `Instrumentation.listening?` memo (reset in specs) | always on | skip repeat subscriber scans |

`AV_PRESSURE_BUILD` / `pressure_build_phase_enabled?` removed. Specs: **714** examples green.

## Documentation cleanup

Removed cooker episode docs, cooker harnesses, and joint multi-gem review content from this repository. Retained light `benchmarks/load.rb`.

## Source

- `lib/active_version/` permanent paths
- JSON encode probe numbers above
