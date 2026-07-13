## Participants

Agent-assisted changelog update for unreleased work on main.

## Decisions

Document user-visible outcomes in CHANGELOG.md under 1.4.0. Keep engineering detail here.

## Effects

Unreleased changes on main (uncommitted at time of writing):

- Add global `revision_error_behavior` (`:exception`, `:log`, `:silent`) and per-model `has_revisions error_behavior:` override.
- Route audit warning output through `ActiveVersion.logger` instead of `Rails.logger`.
- Add `ActiveVersion.log_debug` for deferred setup, instrumentation, and audit payload parse failures.
- Fix audit combiner to reset the cached audits association instead of reloading the auditable record.
- Fix thread-local audited options reader install guard (`method_defined?` instead of `instance_methods`).
- Align audit writer fallback error behavior with configuration default (`:exception`).
- Skip post-update revision bookkeeping when snapshot creation returns nil after log/silent handling.

## Next

Bump `ActiveVersion::VERSION` and tag when cutting the release.

## Source

Working tree diff on main; specs in `spec/active_version/error_handling_spec.rb`, `spec/active_version/audits/has_audits/audit_combiner_spec.rb`, `spec/active_version/core_helpers_spec.rb`.
