# RFC 0005: Audits

- Feature Name: audits
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0006

## Summary

Record change history on a per-model destination table. Storage modes are `:json_column`, `:yaml_column`, and `:mirror_columns`. Default storage is `:json_column`. The gem does not auto-provision a global audits table.

## Motivation

A single default audits table looks convenient until column mapping and retention differ per domain model. Stacking `audited` on the same class occupies the same method names. RFC 0002 forbids enabling this gem together with `audited` or `paper_trail` on the same model. Storage mode is the file contract of the generated migration.

## Guide-level explanation

Run `rails g active_version:audits Post --storage=json_column`. Migrate. Call `has_audits` on the source. On the destination model call `configure_audit`.

`:json_column` and `:yaml_column` serialize changes into a dedicated column. `:mirror_columns` copies changed attributes onto matching destination columns. Configuration rejects other storage symbols.

Batch SQL writers exist so large updates do not instantiate one audit row per ActiveRecord object in Ruby.

## Reference-level explanation

Allowed storage symbols: `json_column`, `yaml_column`, `mirror_columns`. Default when unset: `json_column`. Other symbols are configuration errors. The destination model owns column mapping through `configure_audit`. The source opts in through `has_audits`.

## Registrar

Storage symbols: `json_column`, `yaml_column`, `mirror_columns`. Methods: `has_audits`, `configure_audit`. Generator: `active_version:audits`.

## Drawbacks

Per-model tables and an explicit storage flag add generator work. `:mirror_columns` requires destination columns to keep pace with source attributes. JSON and YAML columns are harder to index than typed columns.

## Rationale and alternatives

A shared audits table plus JSON metadata would look smaller and would hide per-model column contracts. Audited and PaperTrail already occupy audit and version methods; stacking them is the clash this gem refuses. Doing nothing leaves hosts with no recorded change history or with a second gem on the same class.

## Prior art

Audited and PaperTrail record change history on ActiveRecord models. This RFC keeps storage mode and destination mapping on the host model so SQL stays readable. RFC 0004 covers restore snapshots.

## Unresolved questions

Whether batch SQL insert shape should freeze before a second database adapter.
