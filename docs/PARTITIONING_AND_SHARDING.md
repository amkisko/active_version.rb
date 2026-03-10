# Partitioning and Sharding: Suggestions and Best Practices

This guide covers how to scale and manage ActiveVersion data: connection topology (managed by your app), table partitioning (splitting one table by range or list), and data lifecycle (retention, archiving). Use it when audit/revision/translation tables grow large or when you need isolation and performance.

---

## Overview

| Approach | What it does | When to use |
|----------|--------------|-------------|
| Connection topology (app-managed) | Route version writes/reads via your own ActiveRecord multi-DB/shard setup. | Isolate version data from main DB; separate backup/restore; dedicated connection pool. |
| Table partitioning | Split one logical table into physical partitions (e.g. by month). Database-level; you manage migrations. | Very large audit/revision tables; time-based retention; faster deletes and range queries. |
| Application-level limits | `max_audits`, combining/trimming. | Cap per-record history; keep tables smaller without DB schema changes. |

You can combine them: e.g. route audits to a dedicated DB in app code and partition those tables by time.

---

## Composite keys in Rails vs ActiveVersion (current implementation)

Rails supports composite primary keys on models:

```ruby
class AccountEvent < ApplicationRecord
  self.primary_key = [:tenant_id, :event_id]
end
```

In ActiveVersion, support is currently split by scenario:

| Scenario | Status | Details |
|----------|--------|---------|
| Partitioned version tables (`*_audits`, `*_revisions`, `*_translations`) using composite PK that includes partition key | Supported | ActiveVersion can validate this on PostgreSQL setup when `config.partition_schema_guards_enabled = true`. |
| Source model with Rails composite PK (`self.primary_key = [...]`) | Supported with explicit identity mapping | Configure destination models and source associations with explicit identity columns/resolvers so revisions/translations/audits use full identity maps without splitting/encoding IDs. |
| Source table has multi-column business identity (without making it ActiveRecord PK) | Supported pattern | Keep source `id` as PK, store identity columns (`tenant_id`, `partition_key`, etc.) on source and version tables for direct SQL joins. |

### Practical recommendation (today)

- Use Rails composite PK (`self.primary_key = [...]`) on partitioned version tables when PostgreSQL requires partition-key-inclusive PKs.
- For composite source identities, explicitly configure identity columns/resolvers on source and destination models.
- Persist full source identity columns into version tables (for auditing/querying semantics) without encoding/splitting IDs.

---

## Connection topology (separate database connections)

ActiveVersion does not own connection-topology routing. Connection selection is application responsibility.

### When to use connection-topology routing

- Isolation: Keep main DB smaller; run heavy version/audit queries on a separate instance.
- Backup/restore: Back up or restore version data independently.
- Connection limits: Use a dedicated pool for version tables so they don’t compete with main app traffic.
- Compliance: Store audits on a separate, locked-down database.

### Configuration

```yaml
# config/database.yml
production:
  primary:
    database: myapp_production
    # ...
  audit_db:
    database: myapp_audits
    migrations_paths: db/audit_migrate
    # ...
  revision_db:
    database: myapp_revisions
    migrations_paths: db/revision_migrate
```

Then route via standard Rails mechanisms (`connected_to`, custom connection handlers, role/shard switching) in your app/service layer.

### Best practices

1. Connection pools: Give the shard its own pool size so one app doesn’t exhaust the main DB.
2. Migrations: Use `migrations_paths` (or separate migration dirs) for each shard and run `db:migrate` for that shard.
3. Queries: Ensure query code executes under the intended app-selected connection context (e.g. same service/job connection switching strategy as writes).
4. Atomicity: Writes to the version table and the parent table are on different connections, so they are not in one transaction. Prefer “create parent then write version” and handle failures (e.g. retries or compensating actions).

---

## Table partitioning (PostgreSQL)

Partitioning splits a single logical table into multiple physical tables (e.g. by `created_at` month). PostgreSQL supports declarative partitioning; ActiveVersion does not create partitions for you—you add them in migrations.

### When to use partitioning

- Very large audit/revision tables (e.g. millions of rows).
- Time-based retention: Drop or archive old partitions instead of `DELETE` on a huge table.
- Range queries: Queries like “audits in last 30 days” can be limited to one or few partitions.

### Time-range partitioning (example)

Partition a version/audit table by month on a timestamp column. Use raw SQL in a migration so the table is declaratively partitioned (PostgreSQL 10+). Use your own table and column names.

1. Create partitioned parent table: Define the table with `PARTITION BY RANGE (partition_key)`. The primary key must include the partition key (e.g. `(id, partition_key)`).
2. Create range partitions: Add child tables with `CREATE TABLE ... PARTITION OF parent FOR VALUES FROM (...) TO (...)`.
3. Retention: Drop old partitions with `DROP TABLE partition_name` instead of bulk `DELETE`.

### Best practices for partitioning

1. Partition key: Use a timestamp column for append-only data; match the key to your retention and query patterns.
2. Primary key: Include the partition key in a composite primary key (e.g. `(id, partition_key)`). This requirement applies to audit, revision, and translation tables when partitioned.
3. Indexes: Create indexes on the parent so they apply to all partitions (PostgreSQL 11+). Expression indexes require explicit SQL in migrations.
4. Default partition: A `DEFAULT` partition is a safety net for out-of-range rows, not a long-term solution. Monitor it; if you don’t, missing ranges can hide and data can accumulate silently.
5. Migration from non-partitioned: Backfill the new partitioned table (e.g. month-by-month with batching and an `updated_at` guard), verify counts and sample data, then swap in a controlled cutover.

---

## Partitioning: what to avoid

- Renaming only the parent on cutover. When the parent table is renamed, rename every child partition as well so names stay consistent and tooling stays correct.
- Primary key without partition key. PostgreSQL requires unique constraints (including the primary key) to include the partition key. A plain `(id)` primary key is not valid for partitioned tables. This applies to partitioned audit/revision/translation tables.
- Relying on schema dumps for partition state. If the schema dumper is configured to skip partition tables, `schema.rb` will not reflect the real partition layout. Use migrations and/or separate documentation for partition definitions.
- Using a short delta sync as the full migration. A cutover that only syncs a small window (e.g. a few months around “today”) does not replace a full backfill. Backfill all historical data first.
- Assuming the planner will always prune. For overlap/range queries (e.g. “rows overlapping this interval”), partition pruning may not remove all partitions. If the query filter uses a different column than the partition key, consider denormalizing the partition key (e.g. a date column) and aligning query expectations.

---

## Partitioning: what to consider

- Composite primary keys and APIs. Once the primary key is `(id, partition_key)`, uniqueness is per partition. If clients or APIs expose or assume single-column IDs, document that IDs may be composite or ensure string handling is safe (e.g. no assumptions that IDs are globally unique without the partition key).
- Logical uniqueness must include partition key. For partitioned version tables, keep a unique index that includes both:
  - the logical identity columns used by ActiveVersion (`auditable_type/auditable_id/version` for audits, `source_id/version` for revisions, `source_id/locale` for translations), and
  - the partition key columns.
  This keeps PostgreSQL `ON CONFLICT` behavior correct.
- Default partition as a canary. Treat the default partition as a signal: if rows land there, a range is missing. Monitor its row count and fix missing partitions instead of letting it grow.
- Indexes on the parent. Re-create any indexes on the parent table; they propagate to partitions. Uniqueness must include the partition key.
- Write blocking during cutover. A write-blocking trigger (or equivalent) is often used during the final rename to avoid losing writes. Plan for a short write freeze and ensure application and clients can tolerate it.
- Partition maintenance cadence. Pre-create future partitions (e.g. several months ahead) so inserts never fail for missing ranges. Run a maintenance job to create upcoming partitions and, if you use a default partition, drain or move rows out of it.

---

## Efficient querying: composite IDs in params and URLs

When the primary key is composite (e.g. `(id, partition_key)`), routes and params typically pass a single string (e.g. `"123:2025-01-01"`). To look up records efficiently, convert that string to the array form for `find` and back to a string for `to_param`.

Add `param_to_id` and `id_to_param` to your base model so that:

- param_to_id: Receives the param (e.g. from `params[:id]`); if it contains the delimiter, split into an array of primary key components; otherwise return as-is. Use the result with `Model.find(param_to_id(params[:id]))`.
- id_to_param: Receives the model’s primary key value (array or single value); if it’s an array, join with the delimiter for URLs; otherwise return as-is. Use this in `to_param` or when building URLs.

Example on `ApplicationRecord` (choose a delimiter that cannot appear in your ID components, e.g. `":"` or `"-"`):

```ruby
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  PARAM_DELIMITER = ":"

  def self.param_to_id(param)
    param&.include?(PARAM_DELIMITER) ? param.split(PARAM_DELIMITER) : param
  end

  def self.id_to_param(id)
    id.is_a?(Array) ? id.join(PARAM_DELIMITER) : id
  end
end
```

In partitioned (or composite-key) models, override `to_param` to use the composite key:

```ruby
def to_param
  self.class.id_to_param(id)
end
```

In controllers, use the param when finding the record:

```ruby
def set_record
  @record = Model.find(Model.param_to_id(params[:id]))
end
```

This keeps lookups correct and avoids ad-hoc string splitting or incorrect single-column lookups.

---

## Mixed scenarios: source partitioned + version partitioned

Two cases can exist independently or together:

1. Source table partitioned (domain table is partitioned; recommended with single-column AR PK plus explicit identity columns).
2. Version tables partitioned (audit/revision/translation tables are partitioned).

When they are mixed, treat key design as a first-class contract:

- No parsing/splitting joins: destination/version rows must carry all key columns required to join back to source directly.
- Represent full source identity in version tables: persist every component needed for a direct join.
- Keep logical uniqueness explicit:
  - audits: identity columns + version semantics
  - revisions: source identity + version
  - translations: source identity + locale
- If version tables are partitioned: unique constraints (including PK/UPSERT conflict target) must include partition key columns.

In practice, prefer deterministic SQL joins over encoded IDs in application strings; encoded IDs can be useful for routes, but DB joins should use explicit columns.

### Important caveat for `self.primary_key = [...]` on source models

If you define a composite source PK at the ActiveRecord level, current ActiveVersion internals will still assume single-column source references in several places. That means composite source PK wiring is not fully automatic today for audits/revisions/translations.

For production usage right now, prefer:

1. single-column source PK (`id`) for ActiveVersion linkage,
2. explicit identity columns (`tenant_id`, `source_key`, `partition_key`, etc.) copied into version tables,
3. composite PK + partition key enforcement on partitioned version tables.

---

## Partitioning: must-haves before production

- Composite primary key including the partition key (e.g. `(id, partition_key)`) on partitioned audit, revision, and translation tables.
- ActiveVersion guard (optional): On PostgreSQL, when `config.partition_schema_guards_enabled = true`, ActiveVersion validates partitioned audit/revision/translation tables at setup time and raises if:
  - the primary key is not composite or does not include the partition key columns, or
  - the required unique index does not include both logical key columns and partition key columns.
- Full data migration before cutover. Backfill the partitioned table (e.g. by month, with batching and `updated_at` guards). Do not rely only on a small delta sync.
- Delta sync and count verification before rename. During cutover, sync the tail of the data, compare row counts between old and new tables, and abort if they differ.
- Write-block mechanism and transaction drain. During the final switch: block new writes (e.g. trigger), wait for in-flight transactions to finish, then run delta sync, verify counts, and perform the atomic rename(s).
- Child partition renames. When renaming the parent, rename every child partition so the naming scheme stays consistent.
- Full test cycle. Run the full flow (backfill, cutover, queries, and any API behavior) in dev and staging with production-like data and clients before production.

---

## Data lifecycle and application-level limits

### max_audits

Use `max_audits` to cap how many audit rows are kept per record (oldest are combined or removed, depending on implementation):

```ruby
class Post < ApplicationRecord
  has_audits(max_audits: 100)
end
```

This keeps tables smaller without partitioning and is a good first step before adding DB-level partitioning.

### Retention and archiving

- Revisions: Often kept longer (undo/draft history). Consider partitioning by `created_at` if the table grows very large.
- Audits: Good candidates for time-based retention: partition by month and drop or archive partitions older than N months.
- Archiving: Move old partitions to cold storage or a separate schema before dropping; keep a script or job that creates new partitions and drops/archives old ones.

### Best practices

1. Define retention policy: Decide how long to keep audits/revisions and document it.
2. Automate partition creation: Use a cron job or scheduler to create next month’s partition and drop/archive old ones.
3. Monitor size: Track table and partition sizes; set alerts so you add partitions or adjust retention in time.
4. Test in staging: Run partition creation, backfill, and drop/archive in staging before production.

---

## Quick reference

| Goal | Suggestion |
|------|------------|
| Isolate version DB from main app DB | Use app-managed connection routing / shard switching. |
| Very large audit table, time-based retention | Use table partitioning by `created_at` (e.g. monthly). |
| Limit per-record history without DB changes | Use max_audits and application-level combining. |
| Dedicated connection pool for version tables | Define shard in `database.yml` with its own pool. |
| Drop old data efficiently | Use partitioning and `DROP TABLE partition` instead of bulk `DELETE`. |
| Cross-shard queries | Avoid; query each shard explicitly in app-level connection context. |

For setup and configuration of the gem itself, see [SETUP_IN_EXISTING_PROJECT.md](SETUP_IN_EXISTING_PROJECT.md). For overall configuration, see [README](../README.md#configuration).
