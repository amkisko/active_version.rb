# Migration Guide: From PaperTrail to ActiveVersion

This guide provides step-by-step instructions for migrating from the `paper_trail` gem to `active_version.rb`.

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

The `paper_trail` gem and `active_version.rb` both provide versioning functionality, but with different philosophies:

- **PaperTrail**: Stores **before** state (pre-change snapshot)
- **ActiveVersion**: Stores **after** state (post-change audit) in audits

### When to Migrate

Consider migrating if you need:
- Per-model audit tables for better performance
- JSONB storage for flexible schema
- Integration with translations and revisions
- More granular control over audit storage
- Sharding support for audit tables
- Post-change audit trail (vs pre-change snapshots)

## Compatibility Comparison

| Feature | PaperTrail | ActiveVersion | Notes |
|---------|------------|--------------|-------|
| **Table Structure** | Single `versions` table | Per-model tables or JSONB | ActiveVersion offers more flexibility |
| **Association Name** | `versions` | `audits` | Different name |
| **Version Numbering** | Sequential per model | Sequential per model | Compatible |
| **Data Storage** | `object` (full object state) | `audited_changes` (changes only) | Different approach |
| **Changes Storage** | `object_changes` (optional) | `audited_changes` (required) | ActiveVersion focuses on changes |
| **Context Storage** | `meta` (YAML/JSON) | `audited_context` (JSONB/JSON) | Similar concept |
| **Event Type** | `event` (`create`, `update`, `destroy`) | `action` (`create`, `update`, `destroy`) | Same values |
| **Whodunnit** | `whodunnit` (string) | Via context | ActiveVersion uses context |
| **Item Association** | `item_id`, `item_type` | Model-specific foreign key | ActiveVersion uses direct FK |
| **Options** | `ignore`, `skip`, `only`, `if`, `unless` | `except`, `only`, `if`, `unless` | Similar |
| **Callbacks** | `after_version` | `after_audit`, `around_audit` | Similar |

## Key Differences

### 0. Explicit Provisioning and Storage Tradeoffs

- ActiveVersion expects explicit provisioning of audit/revision/translation models and migrations per domain model.
- ActiveVersion intentionally avoids incremental delta chains and diff/patch persistence for audits/revisions.
- This keeps behavior and schema easier to reason about; storage pressure is addressed through retention, partitioning, and cold storage strategies.

### 1. Data Storage Philosophy

**PaperTrail:**
- Stores the **before** state (pre-change snapshot)
- `version.reify` returns object as it was **before** the change
- Full object state stored in `object` column

**ActiveVersion:**
- Stores the **after** state (post-change audit)
- `audit.audited_changes` contains the changes that were **made**
- Only changes stored, not full object state

### 2. Table Structure

**PaperTrail:**
```ruby
# Single versions table for all models
create_table :versions do |t|
  t.string :item_type, null: false
  t.bigint :item_id, null: false
  t.string :event, null: false
  t.string :whodunnit
  t.text :object
  t.text :object_changes
  t.text :meta
  t.datetime :created_at
end

add_index :versions, [:item_type, :item_id]
```

**ActiveVersion:**
```ruby
# Per-model audit table
create_table :post_audits do |t|
  t.references :post, foreign_key: true
  t.string :action, null: false
  t.jsonb :audited_changes
  t.integer :version, null: false
  t.string :comment
  t.jsonb :audited_context
  t.timestamps
end

add_index :post_audits, [:post_id, :version]
```

### 3. Model Declaration

**PaperTrail:**
```ruby
class Post < ApplicationRecord
  has_paper_trail
end
```

**ActiveVersion:**
```ruby
class Post < ApplicationRecord
  has_audits
end
```

### 4. Querying Versions/Audits

**PaperTrail:**
```ruby
post.versions
post.versions.where(event: 'create')
post.versions.reorder(created_at: :desc)
```

**ActiveVersion:**
```ruby
post.audits
post.audits.creates
post.audits.descending
```

### 5. Reifying Objects

**PaperTrail:**
```ruby
# Get object as it was before this version
version.reify  # Returns Post instance as it was before this change
```

**ActiveVersion:**
```ruby
# Get object at a specific version (reconstructed from audits)
post.audit_revision(version: 2)  # Returns Post instance at version 2
post.audit_revision_at(time)      # Returns Post instance at time
```

## Pre-Migration Checklist

- [ ] Review all models using `has_paper_trail`
- [ ] Document any code using `version.reify`
- [ ] Document any code using `paper_trail` methods
- [ ] Document custom version classes (if using `versions: { class_name: ... }`)
- [ ] Backup your database
- [ ] Test migration in staging environment
- [ ] Review version data volume (for performance planning)
- [ ] Identify any code using `version.whodunnit` directly
- [ ] Document any custom serializers or formats
- [ ] Understand the before/after state difference

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

For each model using `paper_trail`, generate ActiveVersion audit tables:

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

**Important**: Don't drop the old `versions` table yet - you'll need it for data migration.

### Step 4: Update Models

Replace `has_paper_trail` with `has_audits`:

**Before:**
```ruby
class Post < ApplicationRecord
  has_paper_trail only: [:title, :body], ignore: [:updated_at]
end
```

**After:**
```ruby
class Post < ApplicationRecord
  has_audits only: [:title, :body], except: [:updated_at]
end
```

### Step 5: Migrate Data

**Note**: PaperTrail stores "before" state while ActiveVersion stores "after" state. You'll need to convert the data appropriately.

Create a custom migration script:

```ruby
# In Rails console or migration
class MigratePaperTrailToActiveVersion
  def self.migrate(model_class)
    old_versions = PaperTrail::Version.where(item_type: model_class.name)
    count = 0

    old_versions.find_each do |old_version|
      # Convert PaperTrail version to ActiveVersion audit
      audit_data = convert_version_to_audit(old_version, model_class)
      
      # Create audit record
      audit_class = "#{model_class.name}Audit".constantize
      audit_class.create!(audit_data)
      
      count += 1
    end

    count
  end

  private

  def self.convert_version_to_audit(old_version, model_class)
    # Extract changes from object_changes or reconstruct from object
    changes = if old_version.object_changes.present?
      # PaperTrail stores changes in object_changes
      parse_changes(old_version.object_changes)
    else
      # Reconstruct changes from object (before state) and current state
      reconstruct_changes(old_version, model_class)
    end

    # Convert meta to context
    context = old_version.meta || {}
    context['whodunnit'] = old_version.whodunnit if old_version.whodunnit

    {
      "#{model_class.table_name.singularize}_id" => old_version.item_id,
      action: old_version.event,
      audited_changes: changes,
      version: calculate_version(old_version, model_class),
      audited_context: context,
      comment: nil,  # PaperTrail doesn't have comments
      created_at: old_version.created_at,
      updated_at: old_version.created_at
    }
  end

  def self.parse_changes(object_changes)
    # Parse YAML or JSON changes
    if object_changes.is_a?(String)
      YAML.safe_load(object_changes) || {}
    else
      object_changes
    end
  end

  def self.reconstruct_changes(old_version, model_class)
    # This is complex - you need to compare old object with next version
    # For now, return empty hash and let ActiveVersion track new changes
    {}
  end

  def self.calculate_version(old_version, model_class)
    # Count versions up to this one
    PaperTrail::Version
      .where(item_type: model_class.name, item_id: old_version.item_id)
      .where("created_at <= ?", old_version.created_at)
      .count
  end
end

# Usage
MigratePaperTrailToActiveVersion.migrate(Post)
```

### Step 6: Update Code References

#### Association Name Change

**Before (PaperTrail):**
```ruby
post.versions
post.versions.last
```

**After (ActiveVersion):**
```ruby
post.audits
post.audits.last
```

#### Reifying Objects

**Before (PaperTrail):**
```ruby
# Get object as it was before this version
version.reify
post.paper_trail.version_at(time)
post.paper_trail.previous_version
```

**After (ActiveVersion):**
```ruby
# Get object at a specific version
post.audit_revision(version: 2)
post.audit_revision_at(time)
# For previous version, use audit_revision with version - 1
```

#### Whodunnit

**Before (PaperTrail):**
```ruby
version.whodunnit
PaperTrail.request.whodunnit = current_user
```

**After (ActiveVersion):**
```ruby
# Access from context
audit.audited_context['whodunnit']

# Set globally
ActiveVersion.with_context(whodunnit: current_user.id) do
  post.update!(title: "New Title")
end
```

#### Event/Action

**Before (PaperTrail):**
```ruby
version.event  # 'create', 'update', 'destroy'
```

**After (ActiveVersion):**
```ruby
audit.action  # 'create', 'update', 'destroy'
```

### Step 7: Update Queries

**Polymorphic Queries:**
```ruby
# PaperTrail - single table
PaperTrail::Version.where(item_type: 'Post')

# ActiveVersion - per-model table
PostAudit.all
```

**Event Queries:**
```ruby
# PaperTrail
PaperTrail::Version.where(event: 'create')

# ActiveVersion
PostAudit.creates
# or
PostAudit.where(action: 'create')
```

**Whodunnit Queries:**
```ruby
# PaperTrail
PaperTrail::Version.where(whodunnit: current_user.id.to_s)

# ActiveVersion
PostAudit.where("audited_context->>'whodunnit' = ?", current_user.id.to_s)
```

### Step 8: Update Controllers

**Before (PaperTrail):**
```ruby
class ApplicationController < ActionController::Base
  before_action :set_paper_trail_whodunnit

  private

  def set_paper_trail_whodunnit
    PaperTrail.request.whodunnit = current_user&.id&.to_s
  end
end
```

**After (ActiveVersion):**
```ruby
class ApplicationController < ActionController::Base
  before_action :set_active_version_context

  private

  def set_active_version_context
    ActiveVersion.with_context(
      whodunnit: current_user&.id&.to_s,
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
      whodunnit: current_user&.id&.to_s,
      request_uuid: request.uuid,
      remote_address: request.remote_ip
    )
  end
end
```

### Step 9: Remove PaperTrail Gem

Once migration is complete and tested:

```ruby
# Gemfile - remove or comment out
# gem 'paper_trail'
```

```bash
bundle install
```

### Step 10: Drop Old Tables

Create a migration to drop the old `versions` table:

```ruby
class DropVersionsTable < ActiveRecord::Migration[7.0]
  def up
    drop_table :versions if table_exists?(:versions)
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
class MigrateFromPaperTrailToActiveVersion < ActiveRecord::Migration[7.0]
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
    add_index :post_audits, "((audited_context->>'whodunnit'))", name: "index_post_audits_on_whodunnit"

    # Step 2: Migrate data (run custom script)
    # See Data Migration section
  end

  def down
    drop_table :post_audits if table_exists?(:post_audits)
  end
end
```

## Code Migration

### Model Changes

**Simple Case:**
```ruby
# Before
class Post < ApplicationRecord
  has_paper_trail
end

# After
class Post < ApplicationRecord
  has_audits
end
```

**With Options:**
```ruby
# Before
class Post < ApplicationRecord
  has_paper_trail(
    only: [:title, :body],
    ignore: [:updated_at, :internal_notes],
    skip: [:secret_field],
    if: :should_version?,
    meta: { ip: :request_ip }
  )
end

# After
class Post < ApplicationRecord
  has_audits(
    only: [:title, :body],
    except: [:updated_at, :internal_notes, :secret_field],
    if: :should_audit?,
    # Meta goes into context via ActiveVersion.with_context
  )
end
```

### Custom Version Classes

**Before:**
```ruby
class Post < ApplicationRecord
  has_paper_trail versions: { class_name: "PostVersion" }
end

class PostVersion < PaperTrail::Version
  # Custom methods
end
```

**After:**
```ruby
class Post < ApplicationRecord
  has_audits as: PostAudit
end

class PostAudit < ApplicationRecord
  include ActiveVersion::Audits::AuditRecord
  
  belongs_to :post
  
  # Custom methods
  def whodunnit
    audited_context['whodunnit']
  end
end
```

## Data Migration

### Important Considerations

1. **Before vs After State**: PaperTrail stores "before" state, ActiveVersion stores "after" state. You may lose the ability to see exact "before" states, but you gain change tracking.

2. **Object vs Changes**: PaperTrail stores full object state in `object` column. ActiveVersion stores only changes in `audited_changes`. You'll need to reconstruct full state from changes if needed.

3. **Version Numbers**: PaperTrail doesn't have explicit version numbers. You'll need to calculate them based on creation order.

### Migration Script

```ruby
# lib/tasks/migrate_paper_trail.rake
namespace :active_version do
  desc "Migrate PaperTrail versions to ActiveVersion audits"
  task migrate_from_paper_trail: :environment do
    models = [Post, Comment, User]  # Add your models
    
    models.each do |model_class|
      puts "Migrating #{model_class.name}..."
      
      versions = PaperTrail::Version
        .where(item_type: model_class.name)
        .order(:created_at)
      
      audit_class = "#{model_class.name}Audit".constantize
      version_map = {}  # Track version numbers per item
      
      versions.find_each do |version|
        item_id = version.item_id
        version_map[item_id] ||= 0
        version_map[item_id] += 1
        
        # Extract changes
        changes = if version.object_changes.present?
          YAML.safe_load(version.object_changes) || {}
        else
          {}  # Will need to reconstruct or skip
        end
        
        # Build context
        context = version.meta || {}
        context['whodunnit'] = version.whodunnit if version.whodunnit
        
        # Create audit
        audit_class.create!(
          "#{model_class.table_name.singularize}_id" => item_id,
          action: version.event,
          audited_changes: changes,
          version: version_map[item_id],
          audited_context: context,
          created_at: version.created_at,
          updated_at: version.created_at
        )
      end
      
      puts "Migrated #{versions.count} versions for #{model_class.name}"
    end
  end
end
```

Run with:
```bash
rails active_version:migrate_from_paper_trail
```

## Testing

### Validation Checklist

1. **Count Verification:**
```ruby
old_count = PaperTrail::Version.where(item_type: 'Post').count
new_count = PostAudit.count
# Note: Counts might differ if some versions had no changes
puts "Old: #{old_count}, New: #{new_count}"
```

2. **Data Integrity:**
```ruby
# Compare sample records
old_version = PaperTrail::Version.where(item_type: 'Post').first
new_audit = PostAudit.find_by(post_id: old_version.item_id, created_at: old_version.created_at)

raise "Event mismatch!" unless old_version.event == new_audit.action
raise "Whodunnit mismatch!" unless old_version.whodunnit == new_audit.audited_context['whodunnit']
```

3. **Association Verification:**
```ruby
post = Post.first
old_versions_count = post.versions.count  # PaperTrail
new_audits_count = post.audits.count      # ActiveVersion

puts "Old: #{old_versions_count}, New: #{new_audits_count}"
```

4. **New Audits:**
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

1. **Keep Old Tables:**
   - Don't drop `versions` table immediately
   - Keep both systems running temporarily

2. **Revert Code:**
```ruby
# Revert models
class Post < ApplicationRecord
  has_paper_trail  # Back to paper_trail
  # has_audits  # Comment out
end
```

3. **Restore from Backup:**
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

### Issue 1: Missing Object Changes

**Problem:** Some PaperTrail versions might not have `object_changes` if `track_associations` wasn't enabled.

**Solution:** 
- Reconstruct changes from `object` column if possible
- Or mark these as "legacy" and let ActiveVersion track new changes going forward

### Issue 2: Before State Not Available

**Problem:** Code expects `version.reify` to return "before" state, but ActiveVersion stores "after" state.

**Solution:** 
- Update code to use `audit_revision` which reconstructs from changes
- Or maintain PaperTrail for read-only access to old data

### Issue 3: Version Number Calculation

**Problem:** PaperTrail doesn't store explicit version numbers.

**Solution:** Calculate based on creation order (see migration script).

### Issue 4: Association Name Change

**Problem:** Code uses `post.versions` but ActiveVersion uses `post.audits`.

**Solution:** 
- Global find/replace: `versions` → `audits`
- Or create alias: `alias_method :versions, :audits`

### Issue 5: Meta vs Context

**Problem:** PaperTrail uses `meta`, ActiveVersion uses `audited_context`.

**Solution:** Migrate `meta` to `audited_context` during data migration.

### Issue 6: Whodunnit Format

**Problem:** PaperTrail stores `whodunnit` as string, ActiveVersion stores in context.

**Solution:** Extract and store in context during migration (see migration script).

## Additional Resources

- [ActiveVersion README](../README.md)
- [ActiveVersion Configuration](../lib/active_version/configuration.rb)
- [PaperTrail Documentation](https://github.com/paper-trail-gem/paper_trail)

## Support

If you encounter issues during migration:
1. Check this guide's Common Issues section
2. Review ActiveVersion test suite for examples
3. Open an issue on GitHub with migration details
