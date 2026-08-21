# RFC 0002: Problem and positioning

- Feature Name: problem-and-positioning
- Type: Informational
- Status: Stable
- Created: 2026-08-17
- Updated: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0003, RFC 0004, RFC 0005, RFC 0006

## Summary

Version ActiveRecord models through explicit translations, revisions, and audits. Operators generate and wire per-model tables. The gem does not auto-provision a global audits table.

## Motivation

Apps need locale copies, workflow snapshots, and change history on the same model. Stacking PaperTrail and Audited on one class occupies the same method names. This gem forbids enabling ActiveVersion together with `audited` or `paper_trail` on the same model.

Implicit global defaults hide the destination schema. A single default audits table looks convenient until column mapping, storage mode, and retention differ per domain model. ActiveVersion puts storage mode and column mapping on the destination model (`configure_audit`, `configure_revision`, `configure_translation`) and requires a generator per model and feature.

Delta-chain or patch persistence reconstructs history at read time. That is costly to implement and debug at scale. ActiveVersion stores straightforward record payloads. Retention, archival, partitioning, or cold storage handle footprint. Optional PostgreSQL triggers and shard routing exist for hosts that need write-path overhead off the Ruby process or version tables on another database.

Those choices are the public contract: generator names, destination-model configuration, storage modes `:json_column`, `:yaml_column`, and `:mirror_columns`, and the trigger SQL. Changing any of them without a numbered RFC breaks existing migrations and models.

## Guide-level explanation

Run `rails g active_version:install`, then a feature generator per model, for example `rails g active_version:audits Post --storage=json_column`. Migrate, include the concerns, and call `has_translations`, `has_revisions`, or `has_audits`. Configure destination models with `configure_audit`, `configure_revision`, and `configure_translation`.

## Drawbacks

Per-model generators and destination classes add setup work. Hosts that wanted one shared history table must map columns per model. Full snapshot rows cost more disk than a patch chain.

## Rationale and alternatives

Explicit per-model tables trade generator work for readable SQL and fewer method clashes. A shared audits table plus JSON metadata would look smaller and would hide per-model column contracts. Patch-chain storage would shrink rows and would make `SELECT` debugging a reconstruction problem. Doing nothing leaves hosts stacking PaperTrail and Audited on the same class.

## Prior art

PaperTrail, Audited, Globalize, and Mobility each solve one of locale copies, snapshots, or audits. This gem puts the three on one explicit wiring path so method names do not collide. Contract detail is RFC 0003 through RFC 0006.

## Unresolved questions

Whether trigger SQL should become a separate RFC from the Ruby API (RFC 0006).

Whether shard routing of version tables needs its own RFC when a second database adapter is added (RFC 0006).
