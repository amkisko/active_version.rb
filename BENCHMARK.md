# Benchmark Report

This document records ActiveVersion benchmark output and optimization guidance.

`usr/bin/benchmark.rb` runs both databases by default and writes logs to:

- `tmp/benchmark_sqlite.log`
- `tmp/benchmark_postgresql.log`
- `tmp/benchmark.log` (combined)

## Workload Defaults

- `ACTIVE_VERSION_BENCH_ITERATIONS=5000`
- `ACTIVE_VERSION_BENCH_WARMUP=200`
- `ACTIVE_VERSION_BENCH_ROUNDS=5`

## Latest Full Run

- Date: 2026-03-09
- Command: `BENCHMARK=1 usr/bin/benchmark.rb`
- Sections executed: SQLite + PostgreSQL

## SQLite Results

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs AR Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `activerecord_baseline` | 1425.27 ms | 1446.45 ms | 1510.52 ms | 0.2823 / 0.2893 / 0.3021 ms | 3508.1 | 1.00x |
| `active_version_audit` | 6231.71 ms | 6231.80 ms | 6327.16 ms | 1.2307 / 1.2464 / 1.2654 ms | 802.3 | 4.37x |
| `db_trigger_audit` | 2067.96 ms | 2069.68 ms | 2121.53 ms | 0.4073 / 0.4139 / 0.4243 ms | 2417.8 | 1.45x |
| `sequel_baseline` | 725.05 ms | 726.07 ms | 737.62 ms | 0.1432 / 0.1452 / 0.1475 ms | 6896.1 | 0.51x |

### SQLite Overhead vs ActiveRecord (Per Record)

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `active_version_audit` | +0.9485 ms | +0.9571 ms | +0.9633 ms |
| `db_trigger_audit` | +0.1250 ms | +0.1246 ms | +0.1222 ms |
| `sequel_baseline` | -0.1391 ms | -0.1441 ms | -0.1546 ms |

## PostgreSQL Results

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs AR Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `activerecord_baseline` | 2265.86 ms | 2276.51 ms | 2380.94 ms | 0.4422 / 0.4553 / 0.4762 ms | 2206.7 | 1.00x |
| `active_version_audit` | 10090.63 ms | 10029.96 ms | 10138.90 ms | 1.9796 / 2.0060 / 2.0278 ms | 495.5 | 4.45x |
| `db_trigger_audit` | 3734.83 ms | 3826.15 ms | 4265.80 ms | 0.6879 / 0.7652 / 0.8532 ms | 1338.7 | 1.65x |
| `sequel_baseline` | 1691.37 ms | 1727.90 ms | 1831.85 ms | 0.3246 / 0.3456 / 0.3664 ms | 2956.2 | 0.75x |

### PostgreSQL Overhead vs ActiveRecord (Per Record)

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `active_version_audit` | +1.5374 ms | +1.5507 ms | +1.5516 ms |
| `db_trigger_audit` | +0.2457 ms | +0.3099 ms | +0.3770 ms |
| `sequel_baseline` | -0.1176 ms | -0.1097 ms | -0.1098 ms |

## Interpretation Checklist

1. Compare `active_version_audit` vs `activerecord_baseline` for app-level overhead.
2. Compare `db_trigger_audit` vs baseline for DB-level audit overhead.
3. Compare SQLite vs PostgreSQL deltas for your production-like expectation.
4. Prefer median and p95 over a single run total.

## Optimization Options

You are not at the absolute lowest possible level yet. Main levers:

1. Use database triggers for the hottest write paths.
2. Track fewer fields (`only:` / `except:`).
3. Keep audit schema minimal and index only proven query patterns.
4. Keep active audit tables small (retention and archival).
5. On PostgreSQL, use targeted `jsonb` indexes and partition large audit tables.

## Repro

```bash
cd /Users/amkisko/workflow/github/amkisko/active_version.rb
usr/bin/benchmark.rb
```

Optional overrides:

```bash
BENCHMARK=1 \
ACTIVE_VERSION_BENCH_ITERATIONS=10000 \
ACTIVE_VERSION_BENCH_WARMUP=500 \
ACTIVE_VERSION_BENCH_ROUNDS=7 \
usr/bin/benchmark.rb
```
