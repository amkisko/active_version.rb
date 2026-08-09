# Setting Up ActiveVersion in an Existing Project

This guide walks through adding the ActiveVersion gem to an existing Rails application and enabling translations, revisions, and/or audits on your models.

## Prerequisites

- Ruby >= 3.0
- Rails >= 7.2.3.2 and < 9.0 (with ActiveRecord)
- Database: PostgreSQL recommended for JSONB and optional triggers; SQLite is also supported (uses `json` columns, and `storage: :mirror_columns` works without JSON payload columns)

## Step-by-Step Setup

### 1. Add the gem

In your `Gemfile`:

```ruby
gem "active_version"
```

Then:

```bash
bundle install
```

### 2. Install the initializer

Generate the default configuration file:

```bash
rails g active_version:install
```

This creates `config/initializers/active_version.rb`. You can edit it later to set global options (e.g. `auditing_enabled`, `current_user_method`). For audits, prefer explicit schema on destination audit models instead of global column defaults.

### 3. Choose which features to use

ActiveVersion has three independent features. Add only what you need.

| Feature      | Use case                         | Generator |
|-------------|-----------------------------------|-----------|
| Translations | Locale-based content (i18n)       | `rails g active_version:translations ModelName` |
| Revisions    | Version history, undo/redo       | `rails g active_version:revisions ModelName`    |
| Audits       | Change tracking, compliance      | `rails g active_version:audits ModelName`       |

You can add one, two, or all three to the same model.

### 4. Generate support for each model

For each model you want to version, run the relevant generators. They create migrations and (for revisions/audits) version model classes.

Translations (e.g. `Post`):

```bash
rails g active_version:translations Post
```

Revisions (e.g. `Post`):

```bash
rails g active_version:revisions Post
```

Audits (e.g. `Post`):

```bash
# JSONB storage (PostgreSQL; use for JSON columns)
rails g active_version:audits Post --storage=json_column

# Table storage (works with SQLite; no `audited_changes` JSON payload column required)
rails g active_version:audits Post --storage=mirror_columns
```

- Use `--storage=json_column` if you use PostgreSQL and want JSON audit columns.
- Use `--storage=mirror_columns` for a structured audit table, including SQLite setups where you want direct audited columns instead of JSON payload storage.

### 5. Run migrations

```bash
rails db:migrate
```

### 6. Include the concerns in your model

Add the generated modules and declarations to your model. Example for a model with all three features:

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  include ActiveVersion::Translations::HasTranslations
  include ActiveVersion::Revisions::HasRevisions
  include ActiveVersion::Audits::HasAudits

  has_translations
  has_revisions
  has_audits  # or: has_audits as: PostAudit  (if you have a custom audit model)
end
```

If you used the generators, the version models (e.g. `PostTranslation`, `PostRevision`, `PostAudit`) are created and the generator output may show the exact `has_*` calls. Use the same pattern: include the concern, then call `has_translations` / `has_revisions` / `has_audits` (and `as:` only when you have a custom audit class).

For audits, configure destination schema on the audit model:

```ruby
class PostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  configure_audit do
    storage :json_column # or :yaml_column / :mirror_columns
    action_column :action
    changes_column :audited_changes
    context_column :audited_context
    comment_column :comment
    version_column :version
    user_column :user_id
  end
end
```

For revisions/translations, configure destination schema on those models too:

```ruby
class PostRevision < ApplicationRecord
  include ActiveVersion::Revisions::RevisionRecord

  # keyword style
  configure_revision(version_column: :version, foreign_key: :post_id)

  # or block style
  # configure_revision do
  #   version_column :version
  #   foreign_key :post_id
  # end
end

class PostTranslation < ApplicationRecord
  include ActiveVersion::Translations::TranslationRecord

  # keyword style
  configure_translation(locale_column: :locale, foreign_key: :post_id)

  # or block style
  # configure_translation do
  #   locale_column :locale
  #   foreign_key :post_id
  # end
end
```

### 7. (Optional) Configure the initializer

Edit `config/initializers/active_version.rb` to:

- Set `config.current_user_method` if you use a different method for the current user in audits.
- Set `config.auditing_enabled = false` in specific environments if needed.
- Use global audit column/storage settings only as fallback when audit models do not declare `configure_audit`.
- Keep connection routing/topology in app-level ActiveRecord configuration and connection switching code.
- Keep partition/key/index validation in your migrations and database checks; ActiveVersion follows your configured schema.

## Checklist for Existing Projects

- [ ] Add `gem "active_version"` and run `bundle install`
- [ ] Run `rails g active_version:install`
- [ ] For each model: run the generators you need (`translations`, `revisions`, `audits`)
- [ ] Run `rails db:migrate`
- [ ] Include the concerns and `has_translations` / `has_revisions` / `has_audits` in each model
- [ ] Configure destination audit/revision/translation models with explicit destination-model DSL (`configure_audit`, `configure_revision`, `configure_translation`)
- [ ] (Optional) Set `current_user_method` and other options in the initializer
- [ ] If migrating from another gem: follow the migration guide and run the migrator (see below)

## Runtime adapter (advanced/non-AR)

ActiveVersion uses an ActiveRecord runtime adapter by default. Advanced integrations can swap it:

```ruby
ActiveVersion.runtime_adapter = MyRuntimeAdapter.new
```

Custom runtime adapters must implement:

- `base_connection`
- `connection_for(model_class, version_type)`

Optional capability hooks:

- `supports_transactional_context?(connection)`
- `supports_current_transaction_id?(connection)`

## Adding to a single model (minimal example)

Example: audits only on `Article` with JSONB.

```bash
rails g active_version:install
rails g active_version:audits Article --storage=json_column
rails db:migrate
```

In `app/models/article.rb`:

```ruby
class Article < ApplicationRecord
  include ActiveVersion::Audits::HasAudits
  has_audits
end
```

## Optional: Database triggers

To use PostgreSQL triggers instead of (or in addition to) application-level versioning:

```bash
rails g active_version:triggers Post --type=audit
# or
rails g active_version:triggers Post --type=revision
```

Then run the generated migration. This is optional and mainly for performance or consistency with DB-level logic.

## Migrating from another gem

- From audited: See [MIGRATION_FROM_AUDITED.md](../MIGRATION_FROM_AUDITED.md) for schema mapping, code changes, and data migration (e.g. `ActiveVersion::Migrators::Audited.migrate(Post)`).
- From paper_trail: See [MIGRATION_FROM_PAPER_TRAIL.md](../MIGRATION_FROM_PAPER_TRAIL.md) for concepts and steps.

After migration, use the same setup steps above (generators, migrations, model includes) for the new tables and concerns.

## Reference app and more docs

- Demo app: `examples/rails_demo/` includes a full Rails app with translations, revisions, and audits. See `examples/rails_demo/README.md` and `examples/rails_demo/SETUP.md`.
- Partitioning and topology: [PARTITIONING_AND_SHARDING.md](PARTITIONING_AND_SHARDING.md) — partitioning, connection-topology notes, retention, and best practices.
- Non-AR runtime integrations: [NON_ACTIVE_RECORD.md](NON_ACTIVE_RECORD.md) — runtime adapter contract, capability hooks, and ownership boundaries.
- Configuration: [README – Configuration](../README.md#configuration) and the initializer template in `lib/generators/active_version/install/templates/initializer.rb.erb`.
- API overview: [README – API Reference](../README.md#api-reference).

## Troubleshooting

- Missing version model: If you see a “constant not found” for `PostRevision` or `PostAudit`, ensure the generator was run for that model and the generated model file exists and is loaded (e.g. under `app/models/`).
- SQLite and JSONB: SQLite does not have PostgreSQL `jsonb`; use `json` columns (default migration fallback) or `--storage=mirror_columns` when you want a non-JSON audit shape. API usage stays the same.
- Callbacks not firing: Ensure the model includes the concern and calls `has_revisions` / `has_audits` (and that `ActiveVersion.config.auditing_enabled` is `true` if you use the global switch).
- Composite source primary key (`self.primary_key = [:a, :b]`): Rails supports this and ActiveVersion supports it when destination schemas explicitly carry the full identity and your model configuration (`foreign_key`, `identity_resolver`, `query_constraints`) matches that identity strategy. See [PARTITIONING_AND_SHARDING.md](PARTITIONING_AND_SHARDING.md).
