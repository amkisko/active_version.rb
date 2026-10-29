# Engineering audit and release preparation

## Decisions

- Continue on main while preserving the pre-existing uncommitted changes. Do not commit, tag, push, or publish.
- Retain release version 2.1.0. Reconcile root and appraisal PATH metadata without updating third-party dependency versions.
- Review correctness, executable coverage, workflow triggers and permissions, package boundaries, resource cost, and trace/identity boundaries. Re-audit the changed paths after corrections.

## Effects

- Fix PostgreSQL update audits to store changed-field old/new pairs; quote SQL identifiers and escape the configured polymorphic type. Treat an empty reset session setting as an empty context.
- Generate revision payload columns from the source table schema instead of a title/body placeholder. A generated Rails application now retains integer, boolean, and datetime attributes in history.
- Use ActiveRecord polymorphic_name consistently in audit writing, querying, combining, and batch SQL so inherited model audits remain visible.
- Replace SQL-string assertions with six executable PostgreSQL contracts: update pairs, reset context, revision snapshots, create/destroy versions and inferred type, disabled writes, and quoted names. Keep the missing revision columns rejection spec.
- Align the stale direct debounce merge expectation with the already documented earliest-pre-change contract. Explain single-writer callback/trigger configuration in the setup guide.
- Enable pull-request test runs and restrict the test workflow to contents: read.
- Fix the release confirmation guard in usr/bin/release.rb so EOF refuses publication. An explicit Enter still selects the displayed default. The process-boundary regression test executes the release script with command execution replaced at the operating-system boundary; no publication command runs against a real service. The shared regression was observed first in Favorites: 2 examples, 1 failure before correction and 2 examples, 0 failures after correction. The release specs pass in every repository.
- Final serial JSON report: 711 examples, 0 failures; PostgreSQL trigger contracts 6 examples, 0 failures; generator end-to-end 1 example, 0 failures.
- Required project checks passed: PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres make test (five isolated shard databases); bundle exec rspec spec/integration/postgresql_trigger_contract_spec.rb; bundle exec rspec spec/integration/generators_end_to_end_spec.rb. Environment: Ruby 4.0.2, BUNDLE_PATH=vendor/bundle; the installed native extensions require that Ruby build.
- Build the gem, verify it with Gem::Package#verify, and check that the changelog heading matches the gem version. Compressed package: 77824 bytes; source payload: 348025 bytes across 75 packaged paths. These are compressed versus uncompressed sizes, not interchangeable quantities.
- Cold process measurement on macOS arm64 with /usr/bin/time -l and bundle exec ruby -Ilib: 0.59 CPU seconds, 0.78 elapsed seconds, 52068352 peak RSS bytes. Favorites loads Rails before the engine. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. All measured values fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions, and run git diff --check. All passed. All six assigned repositories remain on main.

## Next

- No confirmed correction remains in the reviewed changes. Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/RSS/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Learned-system training/evaluation and cloud deployment modes do not apply to these library trees. Native memory-boundary mode applies to Polyrun's extension; browser presentation applies to Favorites; HTTP/identity and message companions apply only to repositories that expose those boundaries. Libraries have no independent production health endpoint to assess.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md
