## Dependency

- active_version (this gem)
- Observed in consumer lockfiles at 2.0.0; defect still present on 2.1.1 before this fix
- Consumer configures Audit with a PostgreSQL jsonb audited_changes column

## Symptom

The JSON serializer encoded a Hash before assigning it to a native jsonb column. ActiveRecord then encoded that string again, so PostgreSQL stored a jsonb string scalar. SQL JSON key operators missed fields that the Active Version accessor could still read after parsing.

## Evidence

- Serializers::Json#dump always called ActiveVersion.json_encode for Hash and Array.
- ActiveSupport::JSON.encode of an already-encoded JSON string yields a JSON string scalar (double encode).
- Consumer local check: jsonb_typeof(audited_changes) returned string; audited_changes ? 'user_id' returned false; audit.audited_changes.key?("user_id") returned true.
- Spec coverage: serializers unit examples; PostgreSQL integration example for jsonb_typeof and the ? operator when PostgreSQL is available.

## Suggested fix

Dump Hash and Array unchanged for json and jsonb columns. Keep JSON string dumps for text-backed columns. Keep load parsing for string values so legacy string-shaped jsonb rows still deserialize. Verify SQL key predicates against a native PostgreSQL jsonb column after upgrade.

## Effects

- Serializers::Json accepts native: and skips encode when true.
- AuditRecord.native_json_payload_column? selects native mode from the column type.
- Existing string-shaped jsonb payloads still decode through the accessor.

## Next

- Consumers with historical string-shaped jsonb rows should keep using the accessor (or a one-off cast) for SQL key predicates until those rows are rewritten.

## Source

- Consumer report: Active Version writes audit payloads as JSONB strings
- https://github.com/amkisko/active_version.rb
