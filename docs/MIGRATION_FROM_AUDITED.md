# Migration Guide: From Audited to ActiveVersion

This guide provides step-by-step instructions for migrating from the `audited` gem to `active_version.rb`.

## Table of Contents

1. [Overview](#overview)
2. [Compatibility Comparison](#compatibility-comparison)
3. [Key Differences](#key-differences)
4. [Pre-Migration Checklist](#pre-migration-checklist)
5. [Migration Steps](#migration-steps)
6. [Schema Migration](#schema-migration)
7. [Code Migration](#code-migration)
8. [Data Migration](#data-migration)
9. [Testing](#testing)
10. [Rollback Plan](#rollback-plan)
11. [Common Issues](#common-issues)

## Overview

The `audited` gem and `active_version.rb` both provide audit trail functionality, but with different approaches:

- Audited: Uses a single `audits` table with polymorphic associations
- ActiveVersion: Uses per-model audit tables (e.g., `post_audits`) or JSONB storage

### When to Migrate

Consider migrating if you need:
- Per-model audit tables for better performance
- JSONB storage for flexible schema
- Integration with translations and revisions
- More granular control over audit storage
- Sharding support for audit tables

## Compatibility Comparison

| Feature | Audited | ActiveVersion | Notes |
|---------|---------|---------------|-------|
| Table Structure | Single `audits` table | Per-model tables or JSONB | ActiveVersion offers more flexibility |
| Association Name | `audits` | `audits` | Same |
| Version Numbering | Sequential per model | Sequential per model | Compatible |
| Changes Storage | `audited_changes` (YAML/JSON) | `audited_changes` (JSONB/JSON) | Format compatible |
| Context Storage | `audited_context` (YAML/JSON) | `audited_context` (JSONB/JSON) | Format compatible |
| Comments | `comment` | `comment` | Same |
| User Tracking | `user_id`, `user_type` | Via context | ActiveVersion uses context |
| Actions | `create`, `update`, `destroy` | `create`, `update`, `destroy` | Same |
| Options | `only`, `except`, `if`, `unless`, `max_audits`, `redacted` | `only`, `except`, `if`, `unless`, `max_audits`, `redacted` | Compatible |
| Callbacks | `after_audit`, `around_audit` | `after_audit`, `around_audit` | Same |

## Key Differences

### 0. Explicit Provisioning and Storage Tradeoffs

- ActiveVersion expects you to explicitly provision audit/revision/translation models and migrations per domain model.
- ActiveVersion does not implement incremental delta chains or diff/patch persistence for audits/revisions.
- This is intentional: the project favors readable schema and operational simplicity; storage growth is handled with retention and archival strategies.

### 1. Table Structure

Audited:
```ruby
# Single audits table for all models
create_table :audits do |t|
  t.references :auditable, polymorphic: true
  t.references :user, polymorphic: true
  t.string :action
  t.text :audited_changes
  t.integer :version
  t.string :comment
  t.text :audited_context
  t.timestamps
end
```

ActiveVersion:
```ruby
# Per-model audit table
create_table :post_audits do |t|
  t.references :post, foreign_key: true
  t.string :action
  t.jsonb :audited_changes  # or text for JSON
  t.integer :version
  t.string :comment
  t.jsonb :audited_context  # or text for JSON
  t.timestamps
end
```

### 2. User Tracking

Audited:
```ruby
# Direct user association
audit.user  # Returns user object
audit.user_id
audit.user_type
```

ActiveVersion:
```ruby
# User stored in context
audit.audited_context['user_id']
audit.audited_context['user_type']
# Or use ActiveVersion.context to set globally
```

### 3. Model Declaration

Audited:
```ruby
class Post < ApplicationRecord
  audited
end
```

ActiveVersion:
```ruby
class Post < ApplicationRecord
  has_audits
end
```

### 4. Querying Audits

Audited:
```ruby
post.audits
post.audits.creates
post.audits.updates
post.audits.descending
```

ActiveVersion:
```ruby
post.audits
post.audits.creates
post.audits.updates
post.audits.descending
# Same API
```

## Pre-Migration Checklist

- [ ] Review all models using `audited`
- [ ] Document custom audit classes (if using `:as` option)
- [ ] Document any custom audit queries or scopes
- [ ] Backup your database
- [ ] Test migration in staging environment
- [ ] Review audit data volume (for performance planning)
- [ ] Identify any code using `audit.user` directly
- [ ] Document selected audit storage mode (`:json_column`, `:yaml_column`, or `:mirror_columns`)

## Migration Steps

### Step 1: Install ActiveVersion

```ruby
# Gemfile
gem 'active_version'
```

```bash
bundle install
rails g active_version:install
```

### Step 2: Generate Audit Tables

For each model using `audited`, generate ActiveVersion audit tables:

```bash
# For table-based storage (recommended for migration)
rails g active_version:audits Post --storage=mirror_columns

# For JSONB storage (if you prefer)
rails g active_version:audits Post --storage=json_column
```

This creates:
- Migration file for `post_audits` table
- `PostAudit` model class

### Step 3: Run Schema Migrations

```bash
rails db:migrate
```

Important: Don't drop the old `audits` table yet - you'll need it for data migration.

### Step 4: Update Models

Replace `audited` with `has_audits`:

Before:
```ruby
class Post < ApplicationRecord
  audited only: [:title, :body], max_audits: 100
end
```

After:
```ruby
class Post < ApplicationRecord
  has_audits only: [:title, :body], max_audits: 100
end
```

### Step 5: Migrate Data

Use the built-in migrator:

```ruby
# In Rails console or migration
ActiveVersion::Migrators::Audited.migrate(Post)

# Or with options
ActiveVersion::Migrators::Audited.migrate(Post, dry_run: false)
```

Dry Run First:
```ruby
# Test migration without actually migrating
count = ActiveVersion::Migrators::Audited.migrate(Post, dry_run: true)
puts "Would migrate #{count} records"
```

### Step 6: Update Code References

#### User Tracking

Before (Audited):
```ruby
audit.user
audit.user_id
audit.user_type
```

After (ActiveVersion):
```ruby
# Option 1: Access from context
user_id = audit.audited_context['user_id']
user_type = audit.audited_context['user_type']
user = user_type.constantize.find(user_id) if user_id

# Option 2: Set context globally
ActiveVersion.with_context(user_id: current_user.id, user_type: 'User') do
  post.update!(title: "New Title")
end
```

#### Custom Audit Classes

If you were using custom audit classes:

Before:
```ruby
class Post < ApplicationRecord
  audited as: CustomPostAudit
end
```

After:
```ruby
class Post < ApplicationRecord
  has_audits as: CustomPostAudit
end

# Make sure CustomPostAudit includes ActiveVersion::Audits::AuditRecord
class CustomPostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord
  
  belongs_to :post
end
```

### Step 7: Update Queries

Most queries remain the same, but check for:

Polymorphic Queries:
```ruby
# Audited - single table
Audited::Audit.where(auditable_type: 'Post')

# ActiveVersion - per-model table
PostAudit.all
```

User Queries:
```ruby
# Audited
Audited::Audit.where(user: current_user)

# ActiveVersion
PostAudit.where("audited_context->>'user_id' = ?", current_user.id.to_s)
```

### Step 8: Remove Audited Gem

Once migration is complete and tested:

```ruby
# Gemfile - remove or comment out
# gem 'audited'
```

```bash
bundle install
```

### Step 9: Drop Old Tables

Create a migration to drop the old `audits` table:

```ruby
class DropAuditsTable < ActiveRecord::Migration[7.0]
  def up
    drop_table :audits if table_exists?(:audits)
  end

  def down
    # Recreate if needed for rollback
    # (You should have a backup)
  end
end
```

## Schema Migration

### Example: Complete Migration

```ruby
class MigrateFromAuditedToActiveVersion < ActiveRecord::Migration[7.0]
  def up
    # Step 1: Create new audit tables
    create_table :post_audits do |t|
      t.references :post, null: false, foreign_key: true
      t.string :action, null: false
      t.jsonb :audited_changes
      t.integer :version, null: false
      t.string :comment
      t.jsonb :audited_context
      t.timestamps
    end

    add_index :post_audits, [:post_id, :version]
    add_index :post_audits, :created_at

    # Step 2: Migrate data (run in console or separate migration)
    # ActiveVersion::Migrators::Audited.migrate(Post)
  end

  def down
    drop_table :post_audits if table_exists?(:post_audits)
  end
end
```

## Code Migration

### Model Changes

Simple Case:
```ruby
# Before
class Post < ApplicationRecord
  audited
end

# After
class Post < ApplicationRecord
  has_audits
end
```

With Options:
```ruby
# Before
class Post < ApplicationRecord
  audited(
    only: [:title, :body],
    except: [:internal_notes],
    max_audits: 100,
    redacted: [:password],
    if: :should_audit?,
    comment_required: true
  )
end

# After
class Post < ApplicationRecord
  has_audits(
    only: [:title, :body],
    except: [:internal_notes],
    max_audits: 100,
    redacted: [:password],
    if: :should_audit?,
    comment_required: true
  )
end
```

### Controller Changes

Before (Audited):
```ruby
class ApplicationController < ActionController::Base
  before_action :set_audited_user

  private

  def set_audited_user
    Audited.store[:current_user] = current_user
  end
end
```

After (ActiveVersion):
```ruby
class ApplicationController < ActionController::Base
  before_action :set_active_version_context

  private

  def set_active_version_context
    ActiveVersion.with_context(
      user_id: current_user&.id,
      user_type: current_user&.class&.name,
      request_uuid: request.uuid,
      remote_address: request.remote_ip
    ) do
      yield
    end
  end
end
```

Or use persistent context:

```ruby
class ApplicationController < ActionController::Base
  before_action :set_active_version_context

  private

  def set_active_version_context
    ActiveVersion.with_context!(
      user_id: current_user&.id,
      user_type: current_user&.class&.name,
      request_uuid: request.uuid,
      remote_address: request.remote_ip
    )
  end
end
```

## Data Migration

### Using the Migrator

The migrator handles:
- Converting audit records from `audits` table to model-specific tables
- Preserving version numbers
- Converting `audited_changes` format
- Converting `audited_context` format
- Preserving timestamps

```ruby
# In Rails console
ActiveVersion::Migrators::Audited.migrate(Post)

# For multiple models
[Post, Comment, User].each do |model|
  count = ActiveVersion::Migrators::Audited.migrate(model)
  puts "Migrated #{count} audits for #{model.name}"
end
```

### Manual Migration (if needed)

If you need custom migration logic:

```ruby
class MigratePostAudits < ActiveRecord::Migration[7.0]
  def up
    # Get old audits
    old_audits = Audited::Audit.where(auditable_type: 'Post')
    
    old_audits.find_each do |old_audit|
      PostAudit.create!(
        post_id: old_audit.auditable_id,
        action: old_audit.action,
        audited_changes: old_audit.audited_changes,
        version: old_audit.version,
        comment: old_audit.comment,
        audited_context: old_audit.audited_context || {},
        created_at: old_audit.created_at,
        updated_at: old_audit.updated_at || old_audit.created_at
      )
    end
  end
end
```

## Testing

### Validation Checklist

1. Count Verification:
```ruby
old_count = Audited::Audit.where(auditable_type: 'Post').count
new_count = PostAudit.count
raise "Count mismatch!" unless old_count == new_count
```

2. Data Integrity:
```ruby
# Compare sample records
old_audit = Audited::Audit.where(auditable_type: 'Post').first
new_audit = PostAudit.find_by(version: old_audit.version, post_id: old_audit.auditable_id)

raise "Version mismatch!" unless old_audit.version == new_audit.version
raise "Action mismatch!" unless old_audit.action == new_audit.action
raise "Changes mismatch!" unless old_audit.audited_changes == new_audit.audited_changes
```

3. Association Verification:
```ruby
post = Post.first
old_audits_count = post.audits.count  # Should still work during transition
new_audits_count = post.audits.count  # After migration

raise "Association broken!" unless old_audits_count == new_audits_count
```

4. New Audits:
```ruby
# Test that new audits are created correctly
post = Post.create!(title: "Test")
post.update!(title: "Updated")

audit = post.audits.last
raise "No audit created!" unless audit
raise "Wrong action!" unless audit.action == "update"
```

## Rollback Plan

### If Migration Fails

1. Keep Old Tables:
   - Don't drop `audits` table immediately
   - Keep both systems running temporarily

2. Revert Code:
```ruby
# Revert models
class Post < ApplicationRecord
  audited  # Back to audited
  # has_audits  # Comment out
end
```

3. Restore from Backup:
   - If data was corrupted, restore from backup
   - Re-run migration after fixing issues

### Rollback Migration

```ruby
class RollbackActiveVersionMigration < ActiveRecord::Migration[7.0]
  def up
    # Drop new tables
    drop_table :post_audits if table_exists?(:post_audits)
  end

  def down
    # Recreate if needed
  end
end
```

## Common Issues

### Issue 1: Version Number Conflicts

Problem: Version numbers might conflict if both systems run simultaneously.

Solution: Migrate during maintenance window or ensure only one system is active.

### Issue 2: User Association Missing

Problem: Code expects `audit.user` but ActiveVersion uses context.

Solution: Create a helper method:

```ruby
class PostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord

  def user
    return nil unless audited_context['user_id']
    audited_context['user_type'].constantize.find(audited_context['user_id'])
  rescue
    nil
  end
end
```

### Issue 3: Serialization Format Differences

Problem: YAML vs JSON format differences.

Solution: The migrator handles this automatically, but verify:

```ruby
# Check format
audit.audited_changes.class  # Should be Hash
```

### Issue 4: Missing Context Data

Problem: Old audits might not have context data.

Solution: The migrator preserves existing context or uses empty hash.

### Issue 5: Performance Issues

Problem: Large audit tables cause slow queries.

Solution: 
- Use JSONB indexes for context queries
- Use app-managed connection topology (separate DB/cluster) when needed
- Archive old audits

```ruby
# Add indexes
add_index :post_audits, "((audited_context->>'user_id'))", name: "index_post_audits_on_user_id"
```

## Additional Resources

- [ActiveVersion README](../README.md)
- [ActiveVersion Configuration](../lib/active_version/configuration.rb)
- [Audited Gem Documentation](https://github.com/collectiveidea/audited)

## Support

If you encounter issues during migration:
1. Check this guide's Common Issues section
2. Review ActiveVersion test suite for examples
3. Open an issue on GitHub with migration details
