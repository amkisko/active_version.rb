require "active_version/revisions/has_revisions/revision_queries"
require "active_version/revisions/has_revisions/revision_manipulation"

module ActiveVersion
  module Revisions
    # Concern for models that have revisions
    module HasRevisions
      extend ActiveSupport::Concern
      include RevisionQueries
      include RevisionManipulation

      included do
        # Class methods
        def self.revision_record?
          false
        end

        # Get revision class name
        def self.revision_class
          # Check if a custom revision class was specified
          @revision_class ||= if @custom_revision_class
            apply_revision_table_name!(@custom_revision_class)
          else
            class_name = "#{name}Revision"
            klass = class_name.safe_constantize || begin
              table_based_name = "#{table_name.to_s.classify}Revision"
              table_based_name.safe_constantize || raise(NameError, "Could not find revision class #{class_name}")
            end
            apply_revision_table_name!(klass)
            klass
          end
        end

        # Get revision class name as string
        def self.revision_class_name
          revision_class.name.to_s
        rescue NameError
          "#{name}Revision"
        end

        # Class attributes for revision options
        class_attribute :revision_options, instance_writer: false

        # Set up associations (deferred to avoid constantize errors during module inclusion)
        def self.setup_revision_associations
          return if @revision_associations_setup

          begin
            inverse = nil
            begin
              inverse_name = name.underscore.to_sym
              revision_klass = revision_class
              register_revision_column_mappings_from_destination(revision_klass)
              revision_klass.setup_associations(force: true) if revision_klass.respond_to?(:setup_associations)
              if revision_klass.respond_to?(:source_name) && revision_klass.source_name == inverse_name
                inverse = inverse_name
              end
            rescue NameError
              inverse = nil
            end

            assoc_options = {
              class_name: revision_class_name,
              dependent: :delete_all,
              inverse_of: inverse || false
            }
            assoc_options[:foreign_key] = revision_klass.source_foreign_key if revision_klass&.respond_to?(:source_foreign_key)
            resolver = revision_klass&.source_primary_key
            if resolver.is_a?(Array)
              assoc_options[:primary_key] = resolver.map(&:to_s)
            elsif resolver.is_a?(String) && resolver.present?
              assoc_options[:primary_key] = resolver
            end

            has_many :revisions, **assoc_options
            @revision_associations_setup = true
          rescue NameError
            # Revision class not yet defined, will be set up later
            @revision_associations_setup = false
          end
        end

        # Call setup after class is fully loaded
        setup_revision_associations if name

        # Rollback handling
        after_rollback :clear_rolled_back_revisions
      end

      module ClassMethods
        # Declare that a model has revisions
        def has_revisions(options = {})
          # Store custom revision class if specified
          if options[:as]
            @custom_revision_class = options[:as]
            options = options.except(:as)
          end

          # Normalize and store options
          self.revision_options = normalize_revision_options(options)

          # Register options before resolving revision FK so custom foreign_key
          # is visible while associations are being built.
          ActiveVersion.registry.register(self, :revisions, revision_options)

          # Ensure association is set up after custom class option is known.
          @revision_associations_setup = false
          setup_revision_associations if respond_to?(:setup_revision_associations)

          # Initialize enabled state (default to true)
          @class_revision_enabled = true

          # Set up callbacks based on options
          setup_revision_callbacks(revision_options)

          # Register with version registry (idempotent)
          ActiveVersion.registry.register(self, :revisions, revision_options)
        end

        # Check if model has revisions configured
        def has_revisions?
          revision_options.present?
        end

        # Normalize revision options
        def normalize_revision_options(options)
          {
            on: Array.wrap(options[:on] || [:update]),
            if: options[:if],
            unless: options[:unless],
            auto: options.fetch(:auto, true),
            only: Array.wrap(options[:only] || []).map(&:to_s),
            except: Array.wrap(options[:except] || []).map(&:to_s),
            foreign_key: normalize_identity_columns(options[:foreign_key]),
            identity_resolver: options[:identity_resolver],
            table_name: options[:table_name]
          }
        end

        def normalize_identity_columns(value)
          return nil if value.nil?
          return value.map(&:to_s) if value.is_a?(Array)

          value.to_s
        end

        def apply_revision_table_name!(klass)
          options = ActiveVersion.registry.config_for(self, :revisions) || {}
          custom_table_name = options[:table_name]
          return klass unless custom_table_name && klass.respond_to?(:table_name=)

          klass.table_name = custom_table_name.to_s
          klass
        end

        def register_revision_column_mappings_from_destination(revision_klass)
          return unless revision_klass.respond_to?(:revision_column_for)
          version_column = revision_klass.revision_column_for(:version)
          return unless version_column
          ActiveVersion.column_mapper.register(self, :revisions, :version, version_column)
        end

        # Set up callbacks based on options
        def setup_revision_callbacks(options)
          # Remove existing callbacks first if they exist
          if respond_to?(:_update_callbacks)
            callbacks = _update_callbacks.select { |cb| cb.filter == :create_revision_before_update }
            callbacks.each { |cb| skip_callback(:update, :before, :create_revision_before_update) }
          end

          # If auto is false or on is empty, don't install callbacks automatically
          return if options[:auto] == false || options[:on] == []

          # Install callbacks for specified events
          if options[:on].include?(:update)
            before_update :create_revision_before_update, if: :should_create_revision?
          end
        end

        # Manual callback installation methods
        def revision_on_update
          before_update :create_revision_before_update, if: :should_create_revision?
        end

        # Create snapshots for all records
        def create_snapshots(opts = {})
          scope = opts[:only_missing] ? where.missing(:revisions) : all

          scope.find_each do |record|
            record.create_snapshot!(opts)
          end
        end

        # Disable revisions for a block
        def without_revisions
          callbacks = if respond_to?(:_update_callbacks)
            _update_callbacks.select { |cb| cb.filter == :create_revision_before_update }
          else
            []
          end
          callback_installed = callbacks.any?

          skip_callback(:update, :before, :create_revision_before_update) if callback_installed
          yield
        ensure
          # Restore callback if it was set up
          if callback_installed && revision_options && revision_options[:auto] != false && revision_options[:on].include?(:update)
            set_callback(:update, :before, :create_revision_before_update, if: :should_create_revision?)
          end
        end

        # Enable revisions for a block
        def with_revisions
          revision_was_enabled = class_revision_enabled?
          enable_revisions
          yield
        ensure
          disable_revisions unless revision_was_enabled
        end

        def class_revision_enabled?
          @class_revision_enabled != false
        end
        public :class_revision_enabled?

        private

        def disable_revisions
          @class_revision_enabled = false
        end

        def enable_revisions
          @class_revision_enabled = true
        end
      end

      # Generate SQL for a single revision insert/upsert.
      # Useful for delayed write pipelines where revision rows are inserted later.
      def revision_sql(version: nil, upsert: false, use_old_values: false, only: nil, except: nil, timestamp: Time.current)
        return "" unless persisted?

        version_column = revision_version_column
        revision_class = self.class.revision_class

        base_attrs = snapshot_base_attributes(use_old_values)
        snapshot_attrs = if only
          base_attrs.slice(*Array.wrap(only).map(&:to_s))
        elsif except
          base_attrs.except(*Array.wrap(except).map(&:to_s))
        else
          base_attrs
        end
        snapshot_attrs.delete_if { |k, _v| deleted_column?(k) }

        next_version = version || (current_version + 1)
        revision_attrs = snapshot_attrs.merge(
          active_version_revision_identity_map.transform_keys(&:to_s)
        ).merge(
          version_column.to_s => next_version,
          "created_at" => timestamp,
          "updated_at" => timestamp
        )

        connection = revision_class.connection
        table_name = connection.quote_table_name(revision_class.table_name)
        columns = revision_attrs.keys
        column_list = columns.map { |col| connection.quote_column_name(col) }.join(", ")
        values_list = columns.map { |col| connection.quote(revision_sql_value(revision_attrs[col])) }.join(", ")

        sql = "INSERT INTO #{table_name} (#{column_list}) VALUES (#{values_list})"
        return sql unless upsert

        conflict_cols = revision_identity_columns.map(&:to_s) + [version_column.to_s]
        updatable_columns = columns - conflict_cols - ["id", "created_at"]
        if updatable_columns.empty?
          "#{sql} ON CONFLICT (#{conflict_cols.map { |col| connection.quote_column_name(col) }.join(", ")}) DO NOTHING"
        else
          assignments = updatable_columns.map do |col|
            qcol = connection.quote_column_name(col)
            "#{qcol} = EXCLUDED.#{qcol}"
          end.join(", ")
          "#{sql} ON CONFLICT (#{conflict_cols.map { |col| connection.quote_column_name(col) }.join(", ")}) DO UPDATE SET #{assignments}"
        end
      end

      private

      public

      def active_version_revision_identity_map
        columns = revision_identity_columns
        values = active_version_revision_identity_values

        case values
        when Hash
          values.transform_keys(&:to_s).slice(*columns)
        when Array
          columns.zip(values).to_h
        else
          {columns.first => values}
        end
      end

      def active_version_revision_identity_values
        resolver = self.class.revision_options && self.class.revision_options[:identity_resolver]
        return default_revision_identity_values if resolver.nil?

        case resolver
        when Proc
          resolver.arity.zero? ? instance_exec(&resolver) : resolver.call(self)
        when Array
          resolver.map { |column| public_send(column) }
        else
          public_send(resolver)
        end
      end

      def revision_identity_columns
        Array(self.class.revision_class.source_foreign_key).map(&:to_s)
      end

      def default_revision_identity_values
        columns = revision_identity_columns
        return id if columns.one?

        source_primary_key_columns.map { |column| self[column] }
      end

      def revision_sql_value(value)
        case value
        when Hash, Array
          value.to_json
        when Time, DateTime
          value.utc
        when Date
          value.to_time.utc
        else
          value
        end
      end

      # Get the effective version column for revisions.
      # Respects custom column mappings but falls back to the default
      # revision version column when the mapped column does not exist
      # in the revision table. This mirrors the behavior used for
      # translations and makes custom mappings opt‑in at the schema level.
      def revision_version_column
        column = ActiveVersion.column_mapper.column_for(self.class, :revisions, :version)

        revision_class = self.class.revision_class
        unless revision_class.column_names.include?(column.to_s)
          column = ActiveVersion.config.revision_version_column
        end

        column
      end

      def should_create_revision?
        # Check basic conditions
        # In before_update callbacks, we're already in an update, so assume there are changes
        # The changes hash might be empty at this point, but we're updating so there must be changes
        unless persisted?
          return false
        end

        # Check class-level enabled state (default to true if not set)
        class_enabled = if self.class.instance_variable_defined?(:@class_revision_enabled)
          self.class.instance_variable_get(:@class_revision_enabled)
        else
          true # Default to enabled
        end
        return false unless class_enabled != false

        # Check global enabled state
        # Note: We use config.auditing_enabled for both audits and revisions
        return false unless ActiveVersion.config.auditing_enabled

        # Get revision options (with defaults if not set)
        options = self.class.revision_options || {auto: true, on: [:update]}

        # Check if/unless conditions
        return false unless run_conditional_check(options[:if])
        return false unless run_conditional_check(options[:unless], matching: false)

        true
      end

      def run_conditional_check(condition, matching: true)
        return true if condition.blank?
        return condition.call(self) == matching if condition.respond_to?(:call)
        return send(condition) == matching if respond_to?(condition.to_sym, true)
        true
      end

      def create_revision_before_update
        # Clear version pointer so we're "at" max again after this update
        remove_instance_variable(:@active_version_pointer) if instance_variable_defined?(:@active_version_pointer)
        # Check if we should create revision
        return unless should_create_revision?

        result = create_snapshot!(use_old_values: true)

        # Ensure revision is persisted and visible in association
        unless result.persisted?
          error_msg = "Failed to create revision: #{result.errors.full_messages.join(", ")}" if result.errors.any?
          error_msg ||= "Revision was not persisted after save!"
          error_msg += "\nRevision: #{result.inspect}"
          error_msg += "\nRevision valid?: #{result.valid?}"
          raise error_msg
        end

        # Clear association cache to ensure revision is visible
        revisions.reset
        result
      end

      def clear_rolled_back_revisions
        revisions.reset
      end
    end
  end
end
