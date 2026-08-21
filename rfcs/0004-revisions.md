# RFC 0004: Revisions

- Feature Name: revisions
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0006

## Summary

Store workflow snapshots of a source model as full record payloads on a per-model destination table. Operators read `current_version`, restore with `undo!`, and load a snapshot with `at_version`.

## Motivation

Patch-chain persistence shrinks rows and makes `SELECT` debugging a reconstruction problem. Apps still need named snapshots they can restore during a workflow. Changing `current_version` or `undo!` without a numbered RFC breaks hosts that already encoded workflow on those methods.

## Guide-level explanation

Run `rails g active_version:revisions Post`. Migrate. Call `has_revisions` on the source. On the destination model call `configure_revision` with version and foreign-key columns.

`current_version` is the live version number on the source. `at_version(n)` loads that snapshot. `undo!` restores the previous stored revision. Optional `append:` writes a new version instead of moving the pointer.

## Reference-level explanation

Each revision row is a complete payload for one source row at one version number. Restore copies that payload back onto the source. `undo!` without `append:` moves the pointer to the previous stored revision. `undo!(append: true)` writes a new revision from the restored payload. Missing destination configuration is a host error.

## Registrar

Public methods: `has_revisions`, `configure_revision`, `current_version`, `at_version`, `undo!`. Generator: `active_version:revisions`.

## Drawbacks

Full payloads cost more disk than a patch chain. Retention, archival, and partitioning stay on the host. Every revised model needs its own table.

## Rationale and alternatives

Delta-chain or patch persistence would shrink rows and would make debugging a reconstruction problem. PaperTrail already occupies version methods on many hosts; RFC 0002 forbids stacking it on the same model. Doing nothing leaves workflow snapshots in ad hoc JSON columns with no restore API.

## Prior art

PaperTrail and similar versioning gems store change history, often as patches or YAML. This RFC stores snapshots so `SELECT` on the destination table is the record. RFC 0005 covers audits as change history.

## Unresolved questions

Whether `undo!(append:)` needs a second restore mode when hosts ask for named checkpoints besides a linear pointer.
