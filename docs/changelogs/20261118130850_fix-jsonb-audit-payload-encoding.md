## Participants

Andrei Makarov

## Decisions

- Keep Hash and Array payloads native when the audit changes or context column is json or jsonb so ActiveRecord encodes once.
- Continue encoding to a JSON string for text-backed columns.
- Continue parsing string values on read so legacy double-encoded jsonb rows still load through audited_changes.

## Effects

- Serializers::Json#dump no longer pre-encodes for native json columns.
- Added unit and PostgreSQL integration coverage for native object storage and legacy string load.

## Next

- Cut in 2.1.2; run `make release`. Consumers on jsonb should re-check SQL key operators on new writes after upgrade.

## Source

- docs/dependencies/20261118130850_audit-jsonb-string-payloads.md
