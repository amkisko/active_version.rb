# Polyrun integration

This repo uses [polyrun](https://rubygems.org/gems/polyrun) **`~> 1.3.0`** (development dependency in `active_version.gemspec`) for:

- **Coverage** — stdlib `Coverage` + `Polyrun::Coverage::Rails` in `spec/spec_helper.rb` (no SimpleCov). Output: `coverage/polyrun-fragment-*.json` (Polyrun 1.3+ may include shard and worker segments in the basename; **`merge-coverage`** still matches this glob).
- **CI reports** — `polyrun report-coverage` (Cobertura, JSON, LCOV, console) and `polyrun report-junit` from RSpec JSON.
- **Parallel RSpec** — per-shard PostgreSQL databases (`active_version_test_0`, …) via `Polyrun::Database::Shard.database_url_with_shard`.

## One machine: parallel RSpec + merged coverage

**`bin/polyrun`** (repo wrapper) with **no arguments** invokes Polyrun’s **default parallel run** (same as **`polyrun`** with no subcommand): **`partition.suite: rspec`** in **`polyrun.yml`** makes path resolution explicit; under the hood this is **`parallel-rspec`** / **`run-shards --merge-coverage`** with **`bundle exec rspec`**. **N separate OS processes**, not Ruby threads. Each process gets **`POLYRUN_SHARD_INDEX`**, **`POLYRUN_SHARD_TOTAL`**, and its own spec list from **`polyrun.yml`** → **`partition.paths_file`** / **`spec/spec_paths.txt`**. Before **`plan`** / **`run-shards`**, Polyrun writes **`spec/spec_paths.txt`** from **`partition.paths_build`**. Fragments **`coverage/polyrun-fragment-*.json`** merge into **`coverage/merged.json`**.

```bash
./bin/polyrun
# same as: POLYRUN_WORKERS=5 bundle exec polyrun -c polyrun.yml  (default parallel RSpec)

./bin/polyrun parallel-rspec --workers 5
./bin/polyrun spec/active_version/configuration_spec.rb
bundle exec polyrun parallel-rspec --workers 5 -c polyrun.yml

# Effective config (YAML merge + env): e.g. shard count
bundle exec polyrun -c polyrun.yml config partition.shard_total

# refresh spec/spec_paths.txt only (optional): ./bin/polyrun build-paths

# equivalent: polyrun run-shards --workers 5 -c polyrun.yml --merge-coverage -- bundle exec rspec
```

Any **polyrun** subcommand passes through (`plan`, `config`, `report-coverage`, **`ci-shard-rspec`**, …). **Path-like** arguments (spec paths, globs, existing files) use **polyrun 1.2+ implicit parallel** (shard those paths without naming `start` or `parallel-rspec`). Leading **`-c` / `-v` / `-h` / `--help`** match **`bundle exec polyrun`**. When the first tokens are **RSpec-only flags** (e.g. **`--format`**), **`bin/polyrun`** still uses **`start --workers $POLYRUN_WORKERS -- bundle exec rspec …`**. **`POLYRUN_WORKERS`** caps worker count (default **5**, max **10**).

## One shard (matrix job or local)

Set **`POLYRUN_SHARD_TOTAL`** and **`POLYRUN_SHARD_INDEX`**, then run **`ci-shard-rspec`** (optionally after **`polyrun env`** if you rely on **`polyrun.yml`** **`databases:`** exports). **`bin/polyrun ci-shard-rspec`** delegates to **`bundle exec polyrun`**.

```bash
export POLYRUN_SHARD_TOTAL=5
export POLYRUN_SHARD_INDEX=0
eval "$(bundle exec polyrun -c polyrun.yml env --shard "$POLYRUN_SHARD_INDEX" --total "$POLYRUN_SHARD_TOTAL")"
./bin/polyrun ci-shard-rspec
```

## Serial run (optional — debugging a single file or `--fail-fast`)

Use the normal RSpec binstub **`bin/rspec`** (plain **`bundle exec rspec`** — no polyrun fan-out):

```bash
bin/rspec
bin/rspec spec/path/to/file_spec.rb --fail-fast
```

The default for **full-suite** runs is **`./bin/polyrun`** (parallel + merged coverage path), not serial **`bin/rspec`**.

## Local PostgreSQL + parallel

Polyrun does not **`CREATE DATABASE`**. With **`DATABASE_URL`** on Postgres and **multiple workers**, each process uses **`…/active_version_test_<n>`** — those databases must exist (same as GitHub Actions).

Create shard DBs once with the shared script (idempotent):

```bash
export DATABASE_URL=postgres://USER@localhost:5432/active_version_test
./script/create_postgres_shard_databases.sh
```

Optional: **`ACTIVE_VERSION_PG_SHARD_BASE`**, **`ACTIVE_VERSION_PG_SHARD_COUNT`** (default **5**, max **10**). Or use **`POLYRUN_WORKERS=1 ./bin/polyrun`** / **`bin/rspec`** for a single database, or run without Postgres to use the SQLite fallback in **`spec/support/database.rb`**.

## Environment

| Variable | Meaning |
|----------|---------|
| `POLYRUN_COVERAGE_DISABLE=1` | Do not start Polyrun coverage in `spec_helper` (e.g. benchmarks). **SimpleCov is not used.** |
| `POLYRUN_COVERAGE=1` | Optional; CI may set this for clarity. Coverage is driven by `Polyrun::Coverage::Rails.start!` in `spec_helper` unless disabled above. |
| `POLYRUN_SHARD_TOTAL` / `POLYRUN_SHARD_INDEX` | Parallel shard; DB URL gets a `_<index>` suffix when using Postgres |
| `POLYRUN_WORKERS` | For **`./bin/polyrun`** default / **`parallel-rspec`** / **`start`**: worker count (default **5**, max **10**) |
| `POLYRUN_MERGE_FORMATS` | Override **`--merge-format`** for post-run merge (default: json, lcov, cobertura, console, html) |
| `POLYRUN_COVERAGE_WORKER_FORMATS=1` | Rare: run per-worker LCOV/HTML formatters in parallel (duplicates work; merged output is canonical) |
| `DEBUG=1` / `POLYRUN_DEBUG=1` | Verbose polyrun stderr trace (timings, shard layout) |

**Parallel runs:** each worker writes **`coverage/polyrun-fragment-*.json`**. Full multi-format reports (LCOV, Cobertura, HTML, etc.) come from **`merge-coverage`** / **`report-coverage`** on the **merged** JSON — not from each worker (avoids N× overhead).

## Other projects

Reuse the same pattern: add the `polyrun` gem (≥ **1.3.0** for **`polyrun config`**, **`partition.suite`**, implicit default parallel run, **`ci-shard-rspec`**, safer **`ci-shard-*`** argv parsing), call `Polyrun::Coverage::Rails.start!` (or `Collector.start!`) in `spec_helper`, add **`polyrun.yml`** (including optional **`partition.paths_build`** to order spec files), a repo **`bin/polyrun`** wrapper (optional) + **`ci-shard-rspec`** for matrix jobs, and wire `Shard.database_url_with_shard` when `POLYRUN_SHARD_TOTAL` > 1.
