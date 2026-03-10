# ActiveVersion

[![Gem Version](https://badge.fury.io/rb/active_version.svg)](https://badge.fury.io/rb/active_version) [![Test Status](https://github.com/amkisko/active_version.rb/actions/workflows/test.yml/badge.svg)](https://github.com/amkisko/active_version.rb/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/amkisko/active_version.rb/graph/badge.svg?token=2U6NXJOVVM)](https://codecov.io/gh/amkisko/active_version.rb)

A unified versioning library for ActiveRecord that handles translations, revisions, and audits in a single, extensible architecture.

## Features

- Translations: Locale-based versioning with automatic value copying
- Revisions: Schema-aligned snapshots for workflow management
- Audits: `:json_column`, `:yaml_column`, or `:mirror_columns` change tracking
- Database Triggers: Optional PostgreSQL triggers for zero-overhead versioning
- Sharding Support: Route version tables to separate databases
- SQL Generation: Batch operations via SQL generation
- Configurable: Flexible column naming and per-model configuration

## Deliberate Differences from PaperTrail, Audited, and Similar Gems

ActiveVersion intentionally chooses explicitness and operational readability over implicit defaults.

- Do not enable ActiveVersion together with `audited` or `paper_trail` on the same model.
  These libraries will start conflicting with each other on method names occupation.
- Manual provisioning is required per model and feature.
  You explicitly generate and wire audits, revisions, and translations tables/models for each domain model. We do not auto-provision global defaults behind the scenes.
  Example: unlike gems that create and rely on a single default audits table automatically, ActiveVersion expects deliberate setup per model.
- Audit schema is configured explicitly on destination audit models.
  Storage mode and audit column mapping belong to the audit model/table contract (`configure_audit`), not hidden global magic.
- Revision/translation schema is also destination-model owned.
  Version/locale and identity key semantics are declared on revision/translation models.
- No incremental/delta-chain storage for revisions or audits.
  ActiveVersion avoids patch-chain persistence and reconstruction complexity as a core design choice.
- No diff/patch-based persistence layer.
  We prefer straightforward record payloads and predictable query/debug behavior.
  Rationale: diff/patch persistence is costly to implement and maintain at scale, while storage footprint is usually manageable with retention policies, archival, partitioning, or cold storage.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_version'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install active_version
```

### Setting up in an existing project

For a step-by-step guide (prerequisites, generators, migrations, model setup, and optional triggers), see [docs/SETUP_IN_EXISTING_PROJECT.md](docs/SETUP_IN_EXISTING_PROJECT.md).

Quick checklist: add the gem → `bundle install` → `rails g active_version:install` → run the feature generators for your models (e.g. `rails g active_version:audits Post --storage=json_column`) → `rails db:migrate` → include the concerns and `has_translations` / `has_revisions` / `has_audits` in each model.

## Quick Start

### Setup

```bash
# Generate initializer
rails g active_version:install
```

### Translations

```ruby
# Generate translation support
rails g active_version:translations Post

# In your model
class Post < ApplicationRecord
  has_translations
end

# Usage
post = Post.create!(title: "Hello", body: "World")
post.translations.create!(locale: "fi", title: "Hei", body: "Maailma")

post.translate(:title, locale: "fi")  # => "Hei"
post.translation(locale: "fi")        # => PostTranslation instance
```

### Revisions

```ruby
# Generate revision support
rails g active_version:revisions Post

# In your model
class Post < ApplicationRecord
  has_revisions
end

# Usage
post = Post.create!(title: "v1")
post.update!(title: "v2")  # Creates revision automatically

post.current_version        # => 1
post.revision(version: 1)   # => PostRevision instance
post.at_version(1)         # => Post instance at version 1
post.undo!                  # => Revert to previous version
post.diff_from(version: 1) # => { "changes" => { "title" => {...} } }
```

### Audits

```ruby
# Generate audit support
rails g active_version:audits Post --storage=json_column

# In your model
class Post < ApplicationRecord
  has_audits
end

# Usage
post = Post.create!(title: "Hello")
post.update!(title: "World")

post.audits.count                    # => 2
post.audits.last.audited_changes      # => {"title" => ["Hello", "World"]}
post.revision(version: 1)            # => Post instance at version 1

# Generate SQL for batch operations
sql = post.audit_sql
PostAudit.batch_insert_sql([post1, post2], force: true)
PostAudit.batch_insert_sql(force: true) { [post1, post2] }
PostRevision.batch_insert_sql(version: 1) do |batch|
  post1 = Post.create!(title: "A")
  post2 = Post.create!(title: "B")
  post3 = Post.create!(title: "C")
  post1.update!(title: "A1")
  post2.update!(title: "B1")
  post3.destroy!
end
PostAudit.batch_insert(force: true) do |batch|
  batch << post1
  batch << post2
end
```

### Batch Semantics and Feature Interaction

- `batch_insert` always executes SQL generated by `batch_insert_sql`.
- By default, clean records are skipped. Use `force: true` or `allow_saved: true` to include them.
- Block mode supports:
  - returning records array
  - collector style (`|batch| batch << record`)
  - callback-capture mode for side-effect blocks (no explicit returned records)
- In batch mode, merge-style features are intentionally not applied:
  - audit compaction (`max_audits` / combine flow) is not executed
  - revision debounce merge window is not executed
- Other behavior still applies from model configuration:
  - identity resolution and foreign key mapping
  - destination schema configuration
  - context merging (`options[:context]` for audit batch helpers)

## Configuration

### Global Configuration

```ruby
# config/initializers/active_version.rb
ActiveVersion.configure do |config|
  config.auditing_enabled = true
  config.current_user_method = :current_user

  # Global fallback naming (prefer destination audit model config instead)
  config.translation_locale_column = :locale
  config.revision_version_column = :version
end
```

### Destination Audit Model Configuration (Preferred)

```ruby
class PostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  configure_audit do
    storage :json_column   # :json_column | :yaml_column | :mirror_columns
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
    comment_column :comment
    version_column :version
    user_column :user_id
  end
end
```

Custom storage providers can be registered per audit model:

```ruby
class PostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  register_storage_provider(:msgpack) do |_audit_class, _column_name|
    MyMsgpackCodec.new # must respond to #load and #dump
  end

  configure_audit do
    storage :msgpack
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
  end
end
```

### Destination Revision/Translation Configuration (Preferred)

```ruby
class PostRevision < ApplicationRecord
  include ActiveVersion::Revisions::RevisionRecord

  configure_revision(version_column: :version,
    foreign_key: :post_id
  )
end

class PostTranslation < ApplicationRecord
  include ActiveVersion::Translations::TranslationRecord

  configure_translation(locale_column: :locale,
    foreign_key: :post_id
  )
end
```

### Per-Model Configuration

```ruby
class Post < ApplicationRecord
  has_audits(
    table_name: "custom_post_audits",
    identity_resolver: :external_id, # optional: use custom identity value for auditable_id
    only: [:title, :body],        # Only track these fields
    except: [:internal_notes],    # Don't track these
    max_audits: 100,               # Limit storage
    associated_with: :company,     # Track associated model
    if: :should_audit?,            # Conditional auditing
    comment_required: true         # Require comments
  )
  
  has_revisions(
    # Revisions are always table-based
    table_name: "custom_post_revisions",
    foreign_key: :record_uuid,         # optional: custom FK column in revision table
    identity_resolver: :external_id    # optional: source value used for FK writes/queries
  )
  
  has_translations(
    # Translations are always table-based
    table_name: "custom_post_translations",
    foreign_key: :record_uuid          # optional: custom FK column in translation table
  )
end
```

## Advanced Features

### Database Triggers

```bash
# Generate trigger for audits
rails g active_version:triggers Post --type=audit

# Generate trigger for revisions
rails g active_version:triggers Post --type=revision
```

### Infrastructure Ownership

```ruby
# Keep infrastructure concerns in application code:
# - connection topology routing / connected_to blocks
# - partition management
# - replication / topology policy
#
# ActiveVersion intentionally does not route between connections/topologies.
# It follows your current ActiveRecord connection and declared model schema.
```

### Runtime Adapter (Advanced)

```ruby
# Default runtime is ActiveRecord-backed.
ActiveVersion.runtime_adapter

# Advanced/non-AR integrations can provide their own adapter object:
# - base_connection
# - connection_for(model_class, version_type)
# Optional capability hooks:
# - supports_transactional_context?(connection)
# - supports_current_transaction_id?(connection)
#
# Example:
# ActiveVersion.runtime_adapter = MyCustomAdapter.new

# Optional boot-time contract check:
# ActiveVersion::Runtime.valid_adapter?(ActiveVersion.runtime_adapter) # => true/false
```

Required adapter contract:

```ruby
class MyCustomAdapter
  def base_connection
    # returns a connection-like object for global/runtime operations
  end

  def connection_for(model_class, version_type)
    # returns the connection-like object used for this source model/type
  end

  # Optional capability hooks. If omitted, ActiveVersion falls back to
  # adapter_name-based PostgreSQL detection.
  def supports_transactional_context?(connection)
    connection.adapter_name.to_s.casecmp("postgresql").zero?
  end

  def supports_current_transaction_id?(connection)
    connection.adapter_name.to_s.casecmp("postgresql").zero?
  end

  def supports_partition_catalog_checks?(connection)
    connection.adapter_name.to_s.casecmp("postgresql").zero?
  end
end
```

See runnable samples:
- [`examples/sinatra_demo/runtime_adapter_example.rb`](examples/sinatra_demo/runtime_adapter_example.rb)
- [`examples/sinatra_demo/sequel_like_runtime_adapter_example.rb`](examples/sinatra_demo/sequel_like_runtime_adapter_example.rb)

For partitioning and connection-topology suggestions, see [docs/PARTITIONING_AND_SHARDING.md](docs/PARTITIONING_AND_SHARDING.md).
For non-ActiveRecord runtime adapter guidance, see [docs/NON_ACTIVE_RECORD.md](docs/NON_ACTIVE_RECORD.md).
For dependency/license disclosure, see [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

### Query Builder

```ruby
# Unified query interface
ActiveVersion::Query.audits(post, preload: :user, order_by: { desc: :created_at })
ActiveVersion::Query.translations(post, locale: "en")
ActiveVersion::Query.revisions(post, version: 2)
```

### Context Tracking

```ruby
# Set global context
ActiveVersion.with_context(ip: request.ip, user_agent: request.user_agent) do
  post.update!(title: "New")
end

# Set per-model context
post.audit_context = { request_id: "123" }
post.save!
```

### Disabling Versioning

```ruby
# Global
ActiveVersion.without_auditing do
  # ...
end

# Per-model
Post.without_auditing do
  # ...
end

# Per-instance
post.without_auditing do
  # ...
end
```

## Migration from Other Gems

### From audited

```ruby
# 1. Generate audit tables
rails g active_version:audits Post --storage=json_column

# 2. Migrate data
ActiveVersion::Migrators::Audited.migrate(Post)

# 3. Update code
# Replace audited with has_audits
```

### From paper_trail

```ruby
# 1. Generate revision tables
rails g active_version:revisions Post

# 2. Migrate data (manual or via migrator)
# 3. Update code
```

## Benchmarking

Benchmarks are available under RSpec with `:benchmark` tag and are excluded from normal runs by default.
Latest published results and analysis are in [BENCHMARK.md](BENCHMARK.md).
The report includes per-record overhead vs ActiveRecord baseline (`p5`, `mean`, `p95`).
The report also separates ActiveRecord and Sequel benchmark groups to avoid cross-ORM baseline mixing.

```bash
# Normal test run (benchmarks excluded)
bundle exec rspec

# Explicit benchmark run
usr/bin/benchmark.rb
```

`usr/bin/benchmark.rb` runs two sections by default: `sqlite` and `postgresql`.

Environment knobs:

- `ACTIVE_VERSION_BENCH_ITERATIONS` (default: `5000`)
- `ACTIVE_VERSION_BENCH_WARMUP` (default: `200`)
- `ACTIVE_VERSION_BENCH_ROUNDS` (default: `5`)
- `BENCHMARK=1` (set automatically by `usr/bin/benchmark.rb`)

## API Reference

### Translations

- `has_translations` - Declare model has translations
- `translate(attr, locale:)` - Get translated attribute
- `translation(locale:)` - Get translation record
- `translated_scopes(*attrs)` - Generate scopes for translated attributes
- `translated_copies(*attrs)` - Generate copy methods

### Revisions

- `has_revisions` - Declare model has revisions
- `current_version` - Get current version number
- `revision(version:)` - Get revision record
- `at_version(version)` - Get copy at version
- `at(time:, version:)` - Get copy at time/version
- `at!(time:, version:)` - Revert to time/version
- `undo!` - Revert to previous version
- `redo!` - Restore to future version
- `switch_to!(version)` - Switch to version
- `diff_from(time:, version:)` - Get diff from time/version
- `create_snapshot!` - Manually create snapshot

### Audits

- `has_audits` - Declare model has audits
- `audit_sql` - Generate SQL for single audit
- `batch_insert_sql(records, **options)` - Generate SQL for batch inserts (also supports block)
- `batch_insert(records, **options)` - Execute batch inserts (also supports block)
- `revision(version:)` - Reconstruct from audits
- `revision_at(time:)` - Reconstruct at time
- `own_and_associated_audits` - Get own and associated audits

## Requirements

- Ruby >= 3.0.0
- ActiveRecord >= 6.0.0 (default runtime)
- SQLite or MySQL or PostgreSQL (optional, for triggers and JSONB support)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amkisko/active_version.rb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Sponsors

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>
