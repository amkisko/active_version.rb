# Benchmark Report

This report uses grouped comparisons so baselines are comparable:

- ActiveRecord group: `activerecord_baseline`, `active_version_audit`, `db_trigger_audit`
- Sequel group: `sequel_baseline`, `sequel_active_version`

`usr/bin/benchmark.rb` runs both SQLite and PostgreSQL by default and writes:

- `tmp/benchmark_sqlite.log`
- `tmp/benchmark_postgresql.log`
- `tmp/benchmark.log` (combined)

## Workload Defaults

- `ACTIVE_VERSION_BENCH_ITERATIONS=5000`
- `ACTIVE_VERSION_BENCH_WARMUP=200`
- `ACTIVE_VERSION_BENCH_ROUNDS=5`

## Latest Full Run

- Date: 2026-03-10
- Command: `BENCHMARK=1 usr/bin/benchmark.rb`
- Sections: SQLite + PostgreSQL

## SQLite

### ActiveRecord Group

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs AR Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `activerecord_baseline` | 1384.63 ms | 1392.38 ms | 1419.87 ms | 0.2745 / 0.2785 / 0.2840 ms | 3611.1 | 1.00x |
| `active_version_audit` | 6320.51 ms | 6331.78 ms | 6377.41 ms | 1.2570 / 1.2664 / 1.2755 ms | 791.1 | 4.56x |
| `db_trigger_audit` | 2029.77 ms | 2030.93 ms | 2041.42 ms | 0.4046 / 0.4062 / 0.4083 ms | 2463.3 | 1.47x |

Overhead vs AR baseline (per record):

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `active_version_audit` | +0.9825 ms | +0.9879 ms | +0.9915 ms |
| `db_trigger_audit` | +0.1301 ms | +0.1277 ms | +0.1243 ms |

### Sequel Group

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs Sequel Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `sequel_baseline` | 710.43 ms | 710.37 ms | 753.11 ms | 0.1370 / 0.1421 / 0.1506 ms | 7038.0 | 1.00x |
| `sequel_active_version` | 3154.62 ms | 3179.11 ms | 3345.04 ms | 0.6220 / 0.6358 / 0.6690 ms | 1585.0 | 4.44x |

Overhead vs Sequel baseline (per record):

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `sequel_active_version` | +0.4850 ms | +0.4937 ms | +0.5184 ms |

## PostgreSQL

### ActiveRecord Group

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs AR Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `activerecord_baseline` | 2297.50 ms | 2409.31 ms | 2630.15 ms | 0.4474 / 0.4819 / 0.5260 ms | 2176.3 | 1.00x |
| `active_version_audit` | 10706.59 ms | 10612.63 ms | 12213.85 ms | 1.8824 / 2.1225 / 2.4428 ms | 467.0 | 4.66x |
| `db_trigger_audit` | 3649.57 ms | 3737.28 ms | 4246.19 ms | 0.6972 / 0.7475 / 0.8492 ms | 1370.0 | 1.59x |

Overhead vs AR baseline (per record):

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `active_version_audit` | +1.4350 ms | +1.6407 ms | +1.9167 ms |
| `db_trigger_audit` | +0.2498 ms | +0.2656 ms | +0.3232 ms |

### Sequel Group

| Scenario | Median Total | Avg Total | P95 Total | Per record p5 / mean / p95 | Ops/s | vs Sequel Baseline |
|---|---:|---:|---:|---:|---:|---:|
| `sequel_baseline` | 1378.18 ms | 1448.60 ms | 1614.69 ms | 0.2701 / 0.2897 / 0.3229 ms | 3628.0 | 1.00x |
| `sequel_active_version` | 5636.54 ms | 5667.94 ms | 5903.73 ms | 1.0926 / 1.1336 / 1.1807 ms | 887.1 | 4.09x |

Overhead vs Sequel baseline (per record):

| Scenario | Overhead p5 | Overhead mean | Overhead p95 |
|---|---:|---:|---:|
| `sequel_active_version` | +0.8225 ms | +0.8439 ms | +0.8578 ms |

## Repro

```bash
cd /Users/amkisko/workflow/github/amkisko/active_version.rb
BENCHMARK=1 usr/bin/benchmark.rb
```

Optional overrides:

```bash
BENCHMARK=1 \
ACTIVE_VERSION_BENCH_ITERATIONS=10000 \
ACTIVE_VERSION_BENCH_WARMUP=500 \
ACTIVE_VERSION_BENCH_ROUNDS=7 \
usr/bin/benchmark.rb
```
