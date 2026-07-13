# CHANGELOG

## 1.3.0 (2026-04-15)

- Add `polyrun` `~> 1.3.0` development dependency; `bin/polyrun`, `bin/rspec`, `polyrun.yml`, and `config/polyrun_coverage.yml` for parallel RSpec and merged coverage.
- Add `script/create_postgres_shard_databases.sh` for CI and local Postgres shard databases; document in `spec/README.md`; set job-level `DATABASE_URL` in GitHub Actions test workflow.
- Add internal library logger.
- Fix audits, Sequel foreign keys, revision debounce, and versions walk edge cases.
- Adjust RSpec and RuboCop test configuration; update spec coverage.

## 1.2.0 (2026-03-27)

- Fixed SQL generation for audit creation to avoid duplicate `created_at` and `updated_at` columns (or other possible duplicate columns)

## 1.1.0 (2026-03-27)

- Added `audit_auditable_optional` configuration option to control polymorphic `belongs_to :auditable` optionality

## 1.0.1 (2026-03-11)

- Fixed Rails 7.2 thread-local audited options handling in `with_audited_options`
- Added Rails 6 appraisal and CI matrix coverage
- Improved test DB connection setup to honor `DATABASE_URL` and fail fast when PostgreSQL is explicitly requested
- Added compatibility fix for ActiveSupport on older Rails with newer Ruby by loading `logger` early
- Updated generator integration spec behavior on TruffleRuby to avoid known native extension incompatibility

## 1.0.0 (2026-03-08)

- Initial release of ActiveVersion library
- Added translations module with locale-based versioning and `has_translations` declaration
- Added `translate(attr, locale:)` and `translation(locale:)` methods for accessing translations
- Added `translated_scopes` for dynamic scopes and `translated_copies` for value copying
- Added automatic default translation creation and locale-based queries
- Added revisions module with schema-aligned snapshots and `has_revisions` declaration
- Added automatic revision creation on update with version numbering
- Added `at_version(version)`, `at(time:, version:)`, and `at!(time:, version:)` methods for version access
- Added `undo!`, `redo!`, and `switch_to!(version)` methods for version control
- Added `diff_from(time:, version:)` for diff generation and `create_snapshot!` for manual snapshots
- Added `without_revisions` for temporarily disabling revision tracking
- Added audits module with JSONB and table storage options and `has_audits` declaration
- Added automatic audit creation on create/update/destroy operations
- Added `audit_sql` for single record SQL generation and `batch_insert_sql` for batch operations
- Added context tracking (global and per-model) for audits
- Added comment support, user tracking, request UUID and remote address tracking
- Added revision reconstruction from audits
- Added conditional auditing with `if:` and `unless:` options
- Added audit combining for storage limits and redaction support for sensitive data
- Added encrypted attributes filtering
- Added PostgreSQL trigger functions for audits and revisions with trigger generators
- Added ability to disable triggers via session variables and context support via session variables
- Added sharding support with connection routing per model, global and per-model shard configuration
- Added `connection_for`, `adapter_for`, and `with_connection` methods for shard management
- Added query builder with `ActiveVersion::Query.audits(record, opts)`, `ActiveVersion::Query.translations(record, opts)`, and `ActiveVersion::Query.revisions(record, opts)` methods
- Added shard-aware queries
- Added migration helpers with `ActiveVersion::Migrators::Base` base class and `ActiveVersion::Migrators::Audited` for audited gem migration
- Added Rails generators: `rails g active_version:install`, `rails g active_version:translations Model`, `rails g active_version:revisions Model`, `rails g active_version:audits Model --storage=json_column`, `rails g active_version:triggers Model --type=audit`
- Added instrumentation hooks via ActiveSupport::Notifications
- Added configurable column naming and per-model and global configuration options
- Added comprehensive test suite with unit tests, integration tests, and test helpers
