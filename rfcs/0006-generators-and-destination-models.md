# RFC 0006: Generators and destination models

- Feature Name: generators-and-destination-models
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003, RFC 0004, RFC 0005

## Summary

Operators generate an initializer, then a feature generator per model. Destination models own column mapping. Optional PostgreSQL triggers and shard routing exist. Translations, revisions, and audits work without them.

## Motivation

Implicit global defaults hide the destination schema. Changing generator names or destination-model configuration without a numbered RFC breaks existing migrations. Coexistence with `audited` and `paper_trail` on the same model is forbidden (RFC 0002).

## Guide-level explanation

Run `rails g active_version:install`, then a feature generator (RFC 0003, RFC 0004, RFC 0005). Include concerns and call `has_translations`, `has_revisions`, or `has_audits`. Configure destination models with `configure_translation`, `configure_revision`, and `configure_audit`.

Optional `rails g active_version:triggers` emits PostgreSQL trigger SQL for hosts that want write-path overhead off the Ruby process. Shard routing of version tables is for hosts that keep those tables on another database.

## Reference-level explanation

Install writes host configuration. Each feature generator writes a migration and a destination model stub for one source model. Destination `configure_*` methods are the column contract. Triggers and shard routing are opt-in; omitting them does not disable translations, revisions, or audits.

## Registrar

Generators: `active_version:install`, `active_version:translations`, `active_version:revisions`, `active_version:audits`, `active_version:triggers`.

## Drawbacks

Every model and feature needs a generator run. Trigger SQL is PostgreSQL-specific. Shard routing adds a second database to operate.

## Rationale and alternatives

Auto-provisioning a global table would hide column mapping until the first production mismatch. Mixing data rewrites into schema migrations is the anti-pattern RFC 0002 rejects for audits and translations alike. Doing nothing leaves hosts copying migration templates by hand.

## Prior art

Rails generators for concern-backed tables (FriendlyId, PaperTrail install generators). PostgreSQL trigger-based audit extensions that move write cost out of Ruby. RFC 0003 through RFC 0005 name the feature generators this RFC installs beside.

## Unresolved questions

Whether trigger SQL should become its own RFC separate from the Ruby API.

Whether shard routing needs its own RFC when a second database adapter is added.
