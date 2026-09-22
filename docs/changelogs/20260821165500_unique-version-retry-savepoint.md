## Decisions

Retry a unique version insert inside a nested transaction so PostgreSQL can continue the outer update or lock transaction after a unique violation.

Each insert pays SAVEPOINT and RELEASE. PostgreSQL aborts the outer transaction unless the failing insert sits on a savepoint, so the first attempt uses the nested transaction too.

Treat these as the same version collision: RecordInvalid when the version column is taken; RecordNotUnique or StatementInvalid caused by PG UniqueViolation when the error text names the version column.

Recalculate MAX(version) without the query cache on retry.

Keep the existing skip of retry on audit create.

Keep a single retry.

## Effects

create_snapshot after undo, inside an open transaction, retries after RecordInvalid on the version uniqueness validation and writes the next revision.

An audit update under with_lock after a concurrent insert writes the next version and the lock transaction continues.

create_snapshot after a planted unique-index row, with uniqueness validation skipped and a stale cached current_version, writes max plus one and the outer transaction continues.

## Next

Quality checks on this branch are done. Open a pull request when ready.

## Source

lib/active_version/unique_version_collision.rb
lib/active_version/revisions/has_revisions/revision_manipulation.rb
lib/active_version/audits/has_audits/audit_writer.rb
spec/active_version/unique_version_collision_spec.rb
spec/integration/revisions_spec.rb
spec/integration/audits_spec.rb
