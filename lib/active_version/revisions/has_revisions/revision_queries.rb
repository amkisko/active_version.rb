module ActiveVersion
  module Revisions
    module HasRevisions
      # Methods for querying revisions
      module RevisionQueries
        extend ActiveSupport::Concern

        # Get revision at specific version
        # Returns a reconstructed instance of the model at that version
        def revision(version: nil)
          return nil unless version

          at_version(version)
        end

        # Get revision at specific time
        def revision_at(time: nil)
          return nil unless time

          time_obj = ActiveVersion.parse_time_to_time(time)
          raise ActiveVersion::FutureTimeError, "Future state cannot be known" if time_obj.future?

          version_column = revision_version_column
          revision_entry = revisions_scope.where("created_at <= ?", time_obj).order(version_column => :desc).first
          # If requested time is before the first revision, return the earliest revision if present.
          revision_entry ||= revisions_scope.order(version_column => :asc).first
          revision_entry
        end

        # Return a copy of record at specified time (read-only)
        def at(time: nil, version: nil)
          if version
            return self if !revisions_scope.exists? && ActiveVersion.config.return_self_if_no_revisions
            return at_version(version)
          end

          time = ActiveVersion.parse_time(time)

          # Validate future time
          if time.future?
            unless ActiveVersion.config.return_self_if_no_revisions
              raise ActiveVersion::FutureTimeError, "Future state cannot be known"
            end
            return self
          end

          # Check if revisions exist
          unless revisions_scope.exists?
            return ActiveVersion.config.return_self_if_no_revisions ? self : nil
          end

          return nil unless exists_at_time?(time)
          return self if current_at_time?(time)

          revision_entry = find_revision_by_time(time)
          build_revision_dup(revision_entry, time) if revision_entry
        end

        # Return a copy of record at specified time (read-only) or raise error
        def at!(time: nil, version: nil)
          result = at(time: time, version: version)
          raise ActiveRecord::RecordNotFound, "No revision found at #{time || version}" unless result
          result
        end

        # Get revision at specific version (read-only)
        def at_version!(version)
          result = at_version(version)
          raise ActiveRecord::RecordNotFound, "No revision found at version #{version}" unless result
          result
        end

        # Get current version number (or version we're at after switch_to!/undo!)
        def current_version
          ptr = instance_variable_get(:@active_version_pointer)
          return ptr if ptr
          version_column = revision_version_column
          revisions_scope.maximum(version_column) || 0
        end

        # Get revision at specific version
        def at_version(version)
          return nil unless version
          version_column = revision_version_column
          revision_entry = revisions_scope.find_by(version_column => version)
          return nil unless revision_entry

          build_revision_dup(revision_entry)
        end

        # Enumerate all versions (lazy enumerator returning revision instances)
        def versions(reverse: false, include_self: false)
          version_column = revision_version_column
          version_list = revisions_scope.order(version_column => (reverse ? :desc : :asc)).pluck(version_column)

          # If include_self, prepare current state as a revision instance
          current_self = nil
          if include_self
            current_self = dup
            current_self.instance_variable_set(:@new_record, false)
            current_self.instance_variable_set(:@persisted, true)
            current_self.readonly!
          end

          Enumerator.new do |yielder|
            version_list.each do |v|
              revision = at_version(v)
              yielder << revision if revision
            end
            if include_self
              yielder << current_self if current_self
            end
          end
        end

        private

        def exists_at_time?(time)
          created_at <= time
        end

        def current_at_time?(time)
          return true if time >= updated_at
          return false unless revisions_scope.any?

          revisions_scope.maximum(:created_at) <= time
        end

        def find_revision_by_time(time)
          version_column = revision_version_column
          revisions_scope.where("created_at <= ?", time).order(version_column => :desc).first
        end

        def revisions_scope
          revision_class = self.class.revision_class
          revision_class.where(active_version_revision_identity_map)
        end

        def build_revision_dup(revision_entry, time = nil)
          return nil unless revision_entry

          dup.tap do |revision|
            version_column = revision_version_column
            foreign_keys = Array(self.class.revision_class.source_foreign_key).map(&:to_s)

            attrs = revision_entry.attributes.except(
              "id",
              "created_at",
              "updated_at",
              version_column.to_s,
              *foreign_keys
            )
            # Filter out deleted columns
            attrs.delete_if { |k, _v| deleted_column?(k) }

            revision.assign_attributes(attrs)
            revision.instance_variable_set(:@new_record, false)
            revision.instance_variable_set(:@persisted, true)
            revision.readonly!

            # Clear association proxies to prevent stale references
            clear_association_proxies(revision)
          end
        end

        def deleted_column?(column)
          return true unless @attributes
          !@attributes.key?(column.to_s)
        end

        def clear_association_proxies(revision)
          revision.instance_variables.each do |ivar|
            proxy = revision.instance_variable_get(ivar)
            if !proxy.nil? && proxy.respond_to?(:proxy_respond_to?)
              revision.instance_variable_set(ivar, nil)
            end
          end
        end
      end
    end
  end
end
