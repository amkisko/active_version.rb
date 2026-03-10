module ActiveVersion
  module Revisions
    module HasRevisions
      # Methods for manipulating revisions
      module RevisionManipulation
        extend ActiveSupport::Concern

        # Create snapshot for this record
        def create_snapshot!(opts = {})
          timestamp = opts[:timestamp] || Time.current
          only_attrs = opts[:only]
          except_attrs = opts[:except]
          use_old_values = opts.fetch(:use_old_values, false)
          version_column = revision_version_column
          batch_state = ActiveVersion.store_get(:active_version_revision_batch_state)
          batch_capture_active = batch_state.is_a?(Hash) && batch_state[:target_revision_class] == self.class.revision_class

          # Check debounce time - merge with previous revision if within window
          debounce_time = opts[:debounce_time] || ActiveVersion.config.debounce_time
          if !batch_capture_active && debounce_time && should_merge_with_previous?(debounce_time, timestamp)
            merge_with_previous_revision!(timestamp, only_attrs, except_attrs, use_old_values)
            version_column = revision_version_column
            return revisions_scope.order(version_column => :desc).first
          end

          new_version = if batch_capture_active
            identity_key = active_version_revision_identity_map.transform_keys(&:to_s).sort.to_h
            tracker = batch_state[:version_tracker] || {}
            current = tracker[identity_key] || current_version
            tracker[identity_key] = current + 1
            batch_state[:version_tracker] = tracker
            current + 1
          else
            current_version + 1
          end

          # Refresh only columns with default functions (query optimization)
          refreshable_columns = refreshable_column_names
          if refreshable_columns.any?
            refreshed = self.class.select(refreshable_columns).find(id)
            refreshable_columns.each do |col|
              refreshed_value = if refreshed.respond_to?(col)
                refreshed.public_send(col)
              elsif refreshed.respond_to?(:[])
                refreshed[col]
              end
              self[col] = refreshed_value
            end
          end

          # Capture base values for the snapshot.
          # For before_update callbacks, prefer persisted values to capture old state.
          base_attrs = snapshot_base_attributes(use_old_values)

          # Filter by only/except if specified
          snapshot_attrs = if only_attrs
            base_attrs.slice(*only_attrs.map(&:to_s))
          elsif except_attrs
            base_attrs.except(*except_attrs.map(&:to_s))
          else
            base_attrs
          end

          # Replace changed attributes with their old values for callback-driven snapshots.
          if use_old_values
            changes_for_snapshot = if respond_to?(:changes_to_save) && changes_to_save.present?
              changes_to_save
            else
              changes
            end
            if changes_for_snapshot.present?
              changes_for_snapshot.each do |attr, values|
                attr_name = attr.to_s
                next unless snapshot_attrs.key?(attr_name)
                next if deleted_column?(attr_name)

                old_value = values.is_a?(Array) ? values[0] : nil
                old_value ||= attribute_was(attr_name) if respond_to?(:attribute_was)
                old_value ||= attribute_in_database(attr_name) if respond_to?(:attribute_in_database)

                snapshot_attrs[attr_name] = old_value unless old_value.nil?
              end
            end
          end

          # Filter out deleted columns
          snapshot_attrs.delete_if { |k, _v| deleted_column?(k) }
          snapshot_attrs.slice!(*revision_payload_columns)

          # version_column is already a symbol from column_mapper
          version_column_sym = version_column.is_a?(Symbol) ? version_column : version_column.to_sym

          # Build revision with explicit foreign key to ensure it's set
          revision_attrs = {
            version_column_sym => new_version,
            :created_at => timestamp,
            :updated_at => timestamp
          }
          revision_attrs.merge!(active_version_revision_identity_map.transform_keys(&:to_sym))
          # Merge snapshot attributes (convert all keys to symbols for ActiveRecord)
          snapshot_attrs.each do |k, v|
            key_sym = k.is_a?(Symbol) ? k : k.to_sym
            revision_attrs[key_sym] = v
          end

          if batch_capture_active
            batch_state[:values] << revision_attrs
            ActiveVersion.store_set(:active_version_revision_batch_state, batch_state)
            pseudo = self.class.revision_class.new(revision_attrs)
            pseudo.define_singleton_method(:persisted?) { true }
            pseudo
          else

            # Use create! instead of build + save to get better error messages
            begin
              revision = revisions.create!(revision_attrs)
            rescue ActiveRecord::RecordInvalid => e
              ActiveVersion::Instrumentation.instrument_revision_write_failed(self, error: e)
              error_msg = "Failed to create revision: #{e.class}"
              error_msg += "\nRevision attribute keys: #{revision_attrs.keys.map(&:to_s).sort.join(", ")}"
              error_msg += "\nIdentity keys: #{active_version_revision_identity_map.keys.map(&:to_s).sort.join(", ")}"
              error_msg += "\nVersion column: #{version_column_sym}, New version: #{new_version}"
              error_msg += "\nRevision class: #{self.class.revision_class.name}"
              error_msg += "\nSource class: #{self.class.name}"
              if e.record
                error_msg += "\nRecord error fields: #{e.record.errors.attribute_names.map(&:to_s).uniq.sort.join(", ")}"
                error_msg += "\nRecord valid?: #{e.record.valid?}"
              end
              raise error_msg
            rescue => e
              ActiveVersion::Instrumentation.instrument_revision_write_failed(self, error: e)
              error_msg = "Failed to create revision: #{e.class}"
              error_msg += "\nRevision attribute keys: #{revision_attrs.keys.map(&:to_s).sort.join(", ")}"
              error_msg += "\nIdentity keys: #{active_version_revision_identity_map.keys.map(&:to_s).sort.join(", ")}"
              error_msg += "\nVersion column: #{version_column_sym}, New version: #{new_version}"
              raise error_msg
            end

            # Force reload association to ensure it's visible
            revisions.reset
            if only_attrs || except_attrs
              excluded_keys = base_attrs.keys - snapshot_attrs.keys
              filtered_keys = revision.attributes.keys - excluded_keys
              revision.instance_variable_set(:@active_version_attributes_filter, filtered_keys)
            end
            revision
          end
        end

        # Revert to a specific version (creates new revision)
        def revert_to(version:)
          from_version = current_version
          target_revision_record = revisions_scope.at_version(version).first
          return false unless target_revision_record

          # Get attributes from revision record (excluding metadata)
          version_column = revision_version_column.to_s
          foreign_keys = revision_identity_columns

          attrs = target_revision_record.attributes.except(
            *source_primary_key_columns,
            "created_at",
            "updated_at",
            *foreign_keys,
            version_column
          )

          update!(attrs)
          ActiveVersion::Instrumentation.instrument_revision_reverted(
            self,
            from_version: from_version,
            to_version: version,
            strategy: :revert_to
          )
          true
        end

        # Restore record to the previous version (second-to-last revision, or latest if only one)
        def undo!(append: false)
          version_column = revision_version_column
          previous = revisions_scope.order(version_column => :desc).offset(1).first ||
            revisions_scope.order(version_column => :desc).first
          return false if previous.nil?

          prev_version = previous.respond_to?(version_column) ? previous.public_send(version_column) : previous[version_column]
          switch_to!(prev_version, append: append)
        end

        # Restore record to the future version (if undo was applied)
        def redo!
          version_column = revision_version_column
          next_rev = revisions_scope.where("#{version_column} > ?", current_version).order(version_column => :asc).first
          return false if next_rev.nil?

          next_version = next_rev.respond_to?(version_column) ? next_rev.public_send(version_column) : next_rev[version_column]
          switch_to!(next_version)
        end

        # Restore record to the specified version
        def switch_to!(version, append: false)
          from_version = current_version
          revision = at_version(version)
          return false unless revision
          version_column = revision_version_column

          if append && version < current_version
            # Create new version with old data instead of reverting
            # This creates a new revision with the target version's data
            target_revision = revisions_scope.where("#{version_column} = ?", version).first
            return false unless target_revision

            foreign_keys = revision_identity_columns
            attrs = target_revision.attributes.except(
              *source_primary_key_columns,
              "created_at",
              "updated_at",
              *foreign_keys,
              version_column.to_s
            )

            # Filter out deleted columns
            attrs.delete_if { |k, _v| deleted_column?(k) }
            attrs.slice!(*revision_payload_columns)

            # Apply the old attributes to the record first (this will be the "old" state for the new revision)
            # Then update to create a new revision that stores the current state (v3) as old, and has v2 as new
            # Actually, we want the new revision to have v2's data, so we need to set the record to v2 first
            # Then when we update, it will create a revision with v3 (current) as old and v2 as new
            # But that's not what we want either...

            # The correct approach: Set record to target state, then create snapshot manually with those attributes
            # But create_snapshot! captures the OLD state before changes...

            # Create revision directly with target attributes, then update record
            version_column_sym = version_column.is_a?(Symbol) ? version_column : version_column.to_sym
            new_version = current_version + 1

            revision_attrs = {
              version_column_sym => new_version,
              :created_at => Time.current
            }
            revision_attrs.merge!(active_version_revision_identity_map.transform_keys(&:to_sym))
            # Add the target version's attributes
            attrs.each do |k, v|
              key_sym = k.is_a?(Symbol) ? k : k.to_sym
              revision_attrs[key_sym] = v
            end

            # Create the revision using the association (it will set foreign_key automatically)
            revision = revisions.create!(revision_attrs)
            # Ensure it was created and persisted
            raise "Failed to create revision" unless revision.persisted?
            # Reload the post to clear all caches and see the new revision
            reload if persisted?
            # Now update the record to match the target version's state.
            # This won't create another revision because we're in without_revisions.
          else
            # To get the state AT version N, use the revision record at version N
            # Revision N stores the state BEFORE version N+1, which is the state AT version N
            revision_record = revisions_scope.where("#{version_column} = ?", version).first

            if revision_record
              # Use the revision record which has the state at version N
              foreign_keys = revision_identity_columns
              attrs = revision_record.attributes.except(
                *source_primary_key_columns,
                "created_at",
                "updated_at",
                *foreign_keys,
                version_column.to_s
              )
            elsif version == current_version
              # Version N is the current version, use current attributes
              attrs = attributes.except(*source_primary_key_columns, "created_at", "updated_at")
            else
              # Fallback: use the revision object from at_version
              foreign_keys = revision_identity_columns
              attrs = revision.attributes.except(
                *source_primary_key_columns,
                "created_at",
                "updated_at",
                *foreign_keys,
                version_column.to_s
              )
            end

            # Filter out deleted columns
            attrs.delete_if { |k, _v| deleted_column?(k) }
            attrs.slice!(*revision_payload_columns)

          end
          assign_attributes(attrs)
          self.class.without_revisions { save! }
          instance_variable_set(:@active_version_pointer, version)
          ActiveVersion::Instrumentation.instrument_revision_switch_applied(
            self,
            from_version: from_version,
            to_version: version,
            append: append
          )
          true
        end

        # Get diff from specific time or version
        def diff_from(time: nil, version: nil)
          raise ArgumentError, "Time or version must be specified" if time.nil? && version.nil?

          version_column = revision_version_column
          from_version = if version
            revisions_scope.find_by(version_column => version)
          else
            find_revision_by_time(ActiveVersion.parse_time(time))
          end

          from_version ||= revisions_scope.order(version_column => :asc).first
          return {"id" => id, "changes" => {}} unless from_version

          from_version_number = from_version.respond_to?(version_column) ? from_version.public_send(version_column) : from_version[version_column]
          base = changes_to(version: from_version_number)
          current_attrs = attributes.except(*source_primary_key_columns, "created_at", "updated_at")
          current = base.merge(current_attrs)

          build_diff(base, current)
        end

        def deleted_column?(column)
          !has_attribute?(column.to_s)
        end

        def apply_revision_diff(version, changes)
          changes.each do |k, v|
            column = k.to_s
            next if deleted_column?(column)
            next unless has_attribute?(column)

            self[column] = deserialize_value(column, v)
          end
          self
        end

        def deserialize_value(column, value)
          return value unless has_attribute?(column)
          @attributes[column.to_s].type.deserialize(value)
        rescue
          value  # Fallback to raw value
        end

        def should_merge_with_previous?(debounce_time, timestamp)
          return false unless revisions_scope.exists?

          version_column = ActiveVersion.column_mapper.column_for(self.class, :revisions, :version)
          last_revision = revisions_scope.order(version_column => :desc).first
          return false unless last_revision

          time_diff = timestamp.to_f - last_revision.created_at.to_f
          time_diff <= debounce_time
        end

        def merge_with_previous_revision!(timestamp, only_attrs, except_attrs, use_old_values)
          version_column = ActiveVersion.column_mapper.column_for(self.class, :revisions, :version)
          last_revision = revisions_scope.order(version_column => :desc).first
          return unless last_revision

          # Update last revision with current or persisted attributes (filtered by only/except)
          base_attrs = snapshot_base_attributes(use_old_values)

          snapshot_attrs = if only_attrs
            base_attrs.slice(*only_attrs.map(&:to_s))
          elsif except_attrs
            base_attrs.except(*except_attrs.map(&:to_s))
          else
            base_attrs
          end

          # Replace changed attributes with their old values
          if use_old_values
            changes_for_snapshot = if respond_to?(:changes_to_save) && changes_to_save.present?
              changes_to_save
            else
              changes
            end
            if changes_for_snapshot.present?
              changes_for_snapshot.each do |attr, values|
                attr_name = attr.to_s
                next unless snapshot_attrs.key?(attr_name)
                next if deleted_column?(attr_name)

                old_value = values.is_a?(Array) ? values[0] : nil
                old_value ||= attribute_was(attr_name) if respond_to?(:attribute_was)
                old_value ||= attribute_in_database(attr_name) if respond_to?(:attribute_in_database)
                snapshot_attrs[attr_name] = old_value unless old_value.nil?
              end
            end
          end

          # Filter out deleted columns
          snapshot_attrs.delete_if { |k, _v| deleted_column?(k) }
          snapshot_attrs.slice!(*revision_payload_columns)

          # When using except, we need to preserve excluded attributes from the existing revision
          except_attrs&.each do |attr|
            attr_str = attr.to_s
            if last_revision.has_attribute?(attr_str) && !snapshot_attrs.key?(attr_str)
              existing_value = last_revision.read_attribute(attr_str)
              snapshot_attrs[attr_str] = existing_value unless existing_value.nil?
            end
          end

          # Update last revision without triggering readonly protection (string keys for update_all)
          update_hash = snapshot_attrs.transform_keys(&:to_s).merge("updated_at" => timestamp)
          last_revision.class.where(id: last_revision.id).update_all(update_hash)
          revisions.reset
        end

        def refreshable_column_names
          @refreshable_column_names ||=
            self.class.columns
              .select(&:default_function)
              .reject { |column| source_primary_key_columns.include?(column.name) }
              .map(&:name)
        end

        def snapshot_base_attributes(use_old_values)
          attrs = if use_old_values
            if respond_to?(:attributes_in_database)
              # Build a full snapshot: start from current attributes, then
              # overlay persisted ("old") values for changed columns.
              # Using only attributes_in_database would keep only changed keys
              # and can drop required NOT NULL columns on revision rows.
              merged = attributes.dup
              attributes_in_database.each do |key, value|
                merged[key] = value
              end
              merged
            else
              attributes.each_with_object({}) do |(k, v), h|
                h[k] = respond_to?(:attribute_in_database) ? attribute_in_database(k) : v
              end
            end
          else
            attributes
          end

          attrs.except(*source_primary_key_columns, "created_at", "updated_at").dup
        end

        def revision_payload_columns
          @revision_payload_columns ||= begin
            revision_class = self.class.revision_class
            foreign_keys = Array(revision_class.source_foreign_key).map(&:to_s)
            version_column = revision_version_column.to_s

            revision_class.column_names - ["id", "created_at", "updated_at", *foreign_keys, version_column]
          end
        end

        def changes_to(version: nil, data: {}, from: 0)
          return data unless version

          foreign_keys = revision_identity_columns
          version_column = revision_version_column.to_s

          revisions_scope.where("#{version_column} >= ? AND #{version_column} <= ?", from, version)
            .order(version_column => :asc)
            .each_with_object(data.dup) do |rev, acc|
              rev.attributes.except(*source_primary_key_columns, "created_at", "updated_at", version_column.to_s, *foreign_keys)
                .each { |k, v| acc[k] = v }
            end
        end

        def build_diff(base, current)
          current.each_with_object({"id" => id, "changes" => {}}) do |(k, v), acc|
            next if deleted_column?(k.to_s)
            unless v == base[k]
              acc["changes"][k] = {"old" => base[k], "new" => v}
            end
          end
        end

        def source_primary_key_columns
          @source_primary_key_columns ||= Array(self.class.primary_key).map(&:to_s)
        end
      end
    end
  end
end
