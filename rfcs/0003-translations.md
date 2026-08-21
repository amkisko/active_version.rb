# RFC 0003: Translations

- Feature Name: translations
- Type: Standards Track
- Status: Stable
- Created: 2026-08-18
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0006

## Summary

Store locale copies of a source model in a per-model destination table. Operators generate that table, call `has_translations` on the source, and map locale and foreign-key columns on the destination. The gem does not auto-provision a global translations table.

## Motivation

Locale copies that share the source row collide on column names and hide which locale a reader is seeing. A second gem occupying `has_translations` on the same class is the clash RFC 0002 forbids. Per-model destination tables keep SQL readable and keep locale as a first-class key.

## Guide-level explanation

Run `rails g active_version:translations Post`. Migrate. Include the translations concern and call `has_translations`. On the destination model call `configure_translation` with locale and foreign-key columns, for example `configure_translation(locale_column: :locale, foreign_key: :post_id)`.

## Reference-level explanation

A translation row belongs to one source row and one locale. The destination model owns column mapping through `configure_translation`. The source model opts in through `has_translations`. Missing generator output or missing `has_translations` is a host configuration error.

## Registrar

Public methods: `has_translations`, `configure_translation`. Generator: `active_version:translations`.

## Drawbacks

Every translated model needs a generator run and a destination class. Hosts that wanted one global translations table must map columns per model instead.

## Rationale and alternatives

A shared translations table plus JSON locale blobs would look smaller and would hide per-model column contracts. Storing locale copies as extra columns on the source table collides with existing attributes and makes `SELECT` locale-blind. Doing nothing leaves hosts stacking a second i18n gem on the same class.

## Prior art

Globalize and Mobility persist locale rows beside a source model and often occupy `has_translations`. Rails I18n covers lookup. RFC 0002 records why this gem also owns revisions and audits.

## Unresolved questions

Whether locale fallback order should freeze when a second adapter is added.
