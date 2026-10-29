Recorded 2026-10-21. Four parallel model audits (core, adapters/DB, tests/contracts, security/hot-path), then parent fact-check against lib/.

## Participants

Andrei Makarov (@amkisko)

## Decisions

- Treat process-wide auditing flags, context bleed via fiber store, at(time:) off-by-one, debounce overwrite, missing migrator action, and mirror redaction bypass as confirmed defects with code evidence.
- Ship smallest credible fixes in 2.1.0; leave trigger/generator/STI/undo-cross-instance items open in the live-work issue.

## Effects

- Confirmed and fixed in tree: without_auditing depth, without_revisions depth (no skip_callback), with_context restore (request-scoped only), Railtie executor to_complete clears persistent context, transactional: false, at/revision_at query, debounce use_old_values keep-earliest, refreshable pending-change skip, Migrators::Audited action and metadata, mirror redaction skip, Configuration error_behavior validate, Rails::Railtie guard, required_ruby_version >= 3.1, README sharding wording, RBS Configuration sync.
- Rejected as injection: batch SQLBuilder quoting (values/identifiers go through connection.quote helpers). Rejected as code exec: YAML.safe_load path.
- Inference left open: cross-instance undo truncate, STI mismatch, trigger empty context outside transaction, concurrent version MAX under load.

## Next

- See docs/issues/20261021190616_engineering-audit-2-1-0.md Next.

## Source

- Multi-model audit pass 2026-10-21
- docs/issues/20261021190616_engineering-audit-2-1-0.md
