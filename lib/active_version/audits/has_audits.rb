require "securerandom"
require "active_version/audits/has_audits/change_filters"
require "active_version/audits/has_audits/audit_callbacks"
require "active_version/audits/has_audits/audit_writer"
require "active_version/audits/has_audits/audit_combiner"

module ActiveVersion
  module Audits
    # Concern for models that have audits
    module HasAudits
      extend ActiveSupport::Concern
      include ChangeFilters
      include AuditCallbacks
      include AuditWriter
      include AuditCombiner

      REDACTED = "[REDACTED]"

      included do
        # Class methods
        def self.audit_record?
          false
        end

        # Get audit class name
        def self.audit_class
          # Check class attribute first (set by set_audit)
          return superclass.audit_class if respond_to?(:superclass) && superclass.respond_to?(:audit_class) && superclass.audit_class
          return @audit_class if @audit_class

          # Check if class attribute was set via class_attribute
          attr_value = read_inheritable_attribute(:audit_class) if respond_to?(:read_inheritable_attribute)
          return attr_value if attr_value

          if audited_options && audited_options[:as]
            klass = case audited_options[:as]
            when String, Symbol
              audited_options[:as].to_s.safe_constantize
            when Class
              audited_options[:as]
            end
            apply_audit_table_name!(klass)
          else
            class_name = "#{name}Audit"
            # Try safe_constantize first (searches global namespace)
            audit_class = if Object.const_defined?(class_name)
              Object.const_get(class_name)
            else
              class_name.safe_constantize
            end
            if audit_class
              apply_audit_table_name!(audit_class)
            elsif const_defined?(class_name, false)
              apply_audit_table_name!(const_get(class_name))
            else
              # Default audit class (would be set in config)
              nil
            end
          end
        end

        # Class attributes
        class_attribute :audit_associated_with, instance_writer: false
        class_attribute :audited_options, instance_writer: false
        class_attribute :audit_class, instance_writer: false

        # Instance attributes
        attr_accessor :audit_version, :audit_comment, :audit_context

        # Define callbacks
        define_callbacks :audit
        set_callback :audit, :after, :after_audit, if: lambda { respond_to?(:after_audit, true) }
        set_callback :audit, :around, :around_audit, if: lambda { respond_to?(:around_audit, true) }
      end

      module ClassMethods
        # Declare that a model has audits
        def has_audits(options = {})
          # For dynamically created classes, require class_name to be explicitly specified
          is_dynamic = name.nil?
          if is_dynamic && !options[:class_name]
            raise ConfigurationError, "Dynamically created classes must specify class_name option. Example: has_audits as: PostAudit, class_name: 'Post'"
          end
          if is_dynamic
            explicit_name = options[:class_name].to_s
            define_singleton_method(:name) { explicit_name } if explicit_name.present? && name.nil?
          end

          # For dynamically created classes, always call set_audit to ensure callbacks are set up
          # For regular classes, update options if already audited
          if audited? && !is_dynamic
            update_audited_options(options)
          else
            set_audit(options)
            # Verify association was set up
            unless reflect_on_association(:audits)
              raise ConfigurationError, "has_audits failed to set up association for #{name || options[:class_name]}. Audit class should be: #{audit_class.inspect}"
            end
          end
        end

        # Check if model is audited (has been set up with has_audits)
        def audited?
          # Check if audited_options is set, which means set_audit has been called
          audited_options.present?
        end

        # Disable auditing for a block
        def without_auditing
          auditing_was_enabled = class_auditing_enabled?
          disable_auditing
          yield
        ensure
          enable_auditing if auditing_was_enabled
        end

        # Enable auditing for a block
        def with_auditing
          auditing_was_enabled = class_auditing_enabled?
          enable_auditing
          yield
        ensure
          disable_auditing unless auditing_was_enabled
        end

        # Get revisions (reconstructed from audits)
        def revisions(from_version = 1)
          return [] unless audits.from_version(from_version).exists?

          version_column = ActiveVersion.column_mapper.column_for(self, :audits, :version)
          all_audits = audits.to_a
          targeted_audits = all_audits.select do |audit|
            audit.read_attribute(version_column).to_i >= from_version
          end

          previous_attributes = audit_class.reconstruct_attributes(all_audits - targeted_audits)

          targeted_audits.map do |audit|
            previous_attributes.merge!(audit.new_attributes)
            revision_with(previous_attributes)
          end
        end

        # Get revision at specific time
        def revision_at(date_or_time)
          time_obj = ActiveVersion.parse_time_to_time(date_or_time)
          # Don't raise error for future times, just return nil (let HasRevisions handle it)
          return nil if time_obj.future?

          version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
          # Reload audits to ensure we get fresh data from database
          audits.reset if respond_to?(:audits) && audits.loaded?
          # Query audits up to and including the time
          # Use < instead of <= to exclude audits created exactly at the time (they represent state after that time)
          # But we want to include audits created at or before the time, so we need to use <=
          # Actually, we want audits created at or before the time, so <= is correct
          audits_list = audits.where("created_at <= ?", time_obj).order(version_column => :asc).to_a
          return nil if audits_list.empty?

          revision_with audit_class.reconstruct_attributes(audits_list)
        end

        private

        def set_audit(options)
          normalized = normalize_audited_options(options)
          # Store base value in instance variable FIRST, before setting class_attribute
          # This ensures class_audited_options can find it
          @audited_options_base = normalized.dup
          self.audited_options = normalized

          # Override audited_options to merge thread-local config
          # class_attribute methods can't be easily overridden, so we need to use alias_method
          unless respond_to?(:audited_options_without_thread_local, true)
            alias_method :audited_options_without_thread_local, :audited_options
            define_singleton_method :audited_options do
              # Get base class-level options (without thread-local)
              # Use send to call private method in correct context
              class_level = send(:class_audited_options)
              key = send(:audited_current_options_key)
              thread_local = ActiveVersion.store_get(key)

              # Start with class-level options (deep copy to avoid reference issues)
              result = if class_level.is_a?(Hash)
                class_level.deep_dup
              else
                {}
              end

              # Merge thread-local over class-level (thread-local takes precedence)
              if thread_local.is_a?(Hash) && !thread_local.empty?
                thread_local.each do |k, v|
                  result[k] = v
                end
              end

              result
            end
          end

          self.audit_associated_with = audited_options[:associated_with]

          # Determine audit class
          resolved_audit_class = if audited_options[:as]
            case audited_options[:as]
            when String, Symbol
              audited_options[:as].to_s.safe_constantize
            when Class
              audited_options[:as]
            end
          else
            # Try to construct class name from model name
            class_name = "#{name}Audit"
            # Try to find the class using safe_constantize first (searches global namespace)
            # Use Object.const_get if defined, otherwise safe_constantize
            audit_class = if Object.const_defined?(class_name)
              Object.const_get(class_name)
            else
              class_name.safe_constantize
            end

            unless audit_class
              # Try const_defined? with inherit=true to search parent classes
              if const_defined?(class_name, true)
                audit_class = const_get(class_name)
              elsif name&.include?("::")
                # Try to find in parent namespace (e.g., if Post is in a module)
                parent_namespace = name.deconstantize
                full_class_name = "#{parent_namespace}::#{class_name}"
                audit_class = full_class_name.safe_constantize
              end
            end

            unless audit_class
              # Fall back to audit class based on table name when model name differs.
              table_based_name = "#{table_name.to_s.classify}Audit"
              audit_class = table_based_name.safe_constantize
            end

            audit_class
          end

          # Fall back to global default audit class when no model-specific audit class exists
          if resolved_audit_class.nil? && ActiveVersion.config.respond_to?(:default_audit_class) && ActiveVersion.config.default_audit_class
            default = ActiveVersion.config.default_audit_class
            resolved_audit_class = case default
            when String, Symbol then default.to_s.safe_constantize
            when Class then default
            end
          end

          unless resolved_audit_class
            raise ConfigurationError, "No audit class found for #{name}. Please specify using :as option or create #{name}Audit. Tried: #{name}Audit"
          end

          # Set both class attribute and instance variable
          apply_audit_table_name!(resolved_audit_class)
          register_audit_column_mappings_from_destination(resolved_audit_class)
          normalized = infer_audit_storage_and_columns(resolved_audit_class, normalized)
          self.audited_options = normalized
          @audited_options_base = normalized.dup
          self.audit_class = resolved_audit_class
          @audit_class = resolved_audit_class  # Also set instance variable for the custom method

          # Ensure audit class associations are set up
          resolved_audit_class.setup_associations if resolved_audit_class.respond_to?(:setup_associations)
          # Set up associations using explicit class_name to avoid class loading issues.
          begin
            has_many :audits,
              as: :auditable,
              class_name: resolved_audit_class.name.to_s,
              inverse_of: false
          rescue => e
            raise ConfigurationError, "Failed to set up has_many association for #{name || normalized[:class_name] || "dynamically created class"}: #{e.class} - #{e.message}"
          end

          # Ensure the association is set up
          unless reflect_on_association(:audits)
            raise ConfigurationError, "Failed to set up audits association for #{name}. Audit class: #{resolved_audit_class.name}, resolved_audit_class: #{resolved_audit_class.inspect}, association found: #{reflect_on_association(:audits).inspect}"
          end

          # Register audit class
          resolved_audit_class.add_audited_class(self)

          # Register with version registry
          ActiveVersion.registry.register(self, :audits, audited_options)
          ActiveVersion.registry.register_version_class(self, :audits, resolved_audit_class)

          # Set up callbacks
          # Allow manual callback installation with on: [] or auto: false
          auto = options.fetch(:auto, true)

          if options[:on] == [] || auto == false
            # User will install manually via audit_on_* methods
          else
            # Install callbacks automatically with conditional checks
            if audited_options[:on].include?(:update)
              before_update :audit_update, if: :should_audit?, prepend: true
            end
            if audited_options[:on].include?(:create)
              after_create :audit_create, if: :should_audit?
            end
            if audited_options[:on].include?(:touch) && ::ActiveRecord::VERSION::MAJOR >= 6
              after_touch :audit_touch, if: :should_audit?
            end
            if audited_options[:on].include?(:destroy)
              before_destroy :audit_destroy, if: :should_audit?
            end
          end

          # Add rollback handling
          after_rollback :clear_rolled_back_audits

          # Comment required validation
          if audited_options[:comment_required]
            validate :presence_of_audit_comment
            before_destroy :require_comment if audited_options[:on].include?(:destroy)
          end

          enable_auditing
        end

        # Override audited_options to merge thread-local config
        # This overrides the class_attribute reader to merge thread-local overrides
        def update_audited_options(new_options)
          normalized = normalize_audited_options(new_options)
          resolved_audit_class = audit_class
          register_audit_column_mappings_from_destination(resolved_audit_class) if resolved_audit_class
          normalized = infer_audit_storage_and_columns(resolved_audit_class, normalized) if resolved_audit_class
          self.audited_options = normalized
          # Store base value in instance variable for class_audited_options to access
          @audited_options_base = normalized.dup
          self.audit_associated_with = audited_options[:associated_with]
        end

        def normalize_audited_options(options)
          {
            on: Array.wrap(options[:on] || [:create, :update, :destroy]),
            only: options.key?(:only) ? Array.wrap(options[:only]).map(&:to_s) : nil,
            except: Array.wrap(options[:except] || []).map(&:to_s),
            max_audits: options[:max_audits],
            redacted: Array.wrap(options[:redacted] || []).map(&:to_s),
            redaction_value: options[:redaction_value] || REDACTED,
            associated_with: options[:associated_with],
            if: options[:if],
            unless: options[:unless],
            auto: options.fetch(:auto, true),
            comment_required: options[:comment_required] || false,
            identity_resolver: options[:identity_resolver],
            identity_columns: normalize_identity_columns(options[:identity_columns]),
            storage: options.key?(:storage) ? options[:storage] : nil,
            as: options[:as],
            class_name: options[:class_name], # For dynamically created classes, specify the class name to use
            error_behavior: options[:error_behavior],
            table_name: options[:table_name]
          }
        end

        def normalize_identity_columns(value)
          return nil if value.nil?
          return value.map(&:to_s) if value.is_a?(Array)

          value.to_s
        end

        public

        def with_audited_options(options = {})
          thread_key = audited_current_options_key
          current = ActiveVersion.store_get(thread_key)
          # Store only the thread-local overrides (merge with existing if any)
          # Only normalize the provided keys, don't set defaults for missing keys
          # Normalize options - convert to hash and process each key
          # Use paper_trail's simple pattern: options.to_h.each
          normalized = {}
          # Convert options to hash (paper_trail pattern: simple to_h call)
          # Handle both Hash and objects that respond to to_h
          opts_hash = if options.respond_to?(:to_h)
            options.to_h
          elsif options.is_a?(Hash)
            options
          else
            {}
          end

          opts_hash.each do |k, v|
            next if v.nil?
            key = k.is_a?(Symbol) ? k : k.to_sym
            # Normalize based on key type
            normalized[key] = case key
            when :only, :except, :redacted
              Array.wrap(v).map(&:to_s)
            when :on
              Array.wrap(v)
            when :max_audits, :redaction_value, :associated_with, :if, :unless, :auto, :comment_required, :storage, :as, :error_behavior
              v
            when :identity_columns
              normalize_identity_columns(v)
            else
              # Allow any other keys to pass through (for extensibility)
              v
            end
          end

          # Merge normalized options with existing thread-local overrides
          # paper_trail pattern: merge into existing, then set
          thread_local_overrides = (current || {}).dup
          thread_local_overrides.merge!(normalized)
          # Set thread-local value - ensure it's a hash so it can be read back
          # Store the merged overrides in Thread.current (use dup to avoid reference issues)
          ActiveVersion.store_set(thread_key, thread_local_overrides.is_a?(Hash) ? thread_local_overrides.dup : {})
          yield
        ensure
          ActiveVersion.store_set(thread_key, current)
        end

        def instance_methods(all = true)
          methods = super
          methods -= [:audit_revision, :audit_revision_at]
          methods
        end

        private

        # Get the base class_attribute value without thread-local merging
        def class_audited_options
          # Try to get from instance variable first (most direct)
          if instance_variable_defined?(:@audited_options_base)
            value = instance_variable_get(:@audited_options_base)
            return value.dup if value&.is_a?(Hash)
          end
          # If not set, try superclass
          if respond_to?(:superclass) && superclass
            if superclass.instance_variable_defined?(:@audited_options_base)
              value = superclass.instance_variable_get(:@audited_options_base)
              if value&.is_a?(Hash)
                # Store it for future use
                @audited_options_base = value.dup
                return value.dup
              end
            end
            # Try calling superclass method if it exists
            if superclass.respond_to?(:class_audited_options, true)
              value = superclass.send(:class_audited_options)
              if value&.is_a?(Hash)
                # Store it for future use
                @audited_options_base = value.dup
                return value.dup
              end
            end
          end
          # Return empty hash if nothing found
          # This ensures merge works correctly even if base is not set
          {}
        end

        def audited_current_options_key
          # Use a consistent key format for thread-local storage
          # This key must match between with_audited_options and audited_options
          # For dynamically created classes, use class_name from options (avoid recursion by checking @audited_options_base)
          class_name = if instance_variable_defined?(:@audited_options_base) && @audited_options_base.is_a?(Hash)
            @audited_options_base[:class_name] || name
          else
            name
          end
          if class_name.nil?
            class_name = "dynamic_#{object_id}"
          end
          "active_version_#{class_name}_audited_options"
        end

        def class_auditing_enabled?
          @class_auditing_enabled != false
        end
        public :class_auditing_enabled?

        def disable_auditing
          @class_auditing_enabled = false
        end

        def enable_auditing
          @class_auditing_enabled = true
        end

        def apply_audit_table_name!(klass)
          return klass unless klass&.respond_to?(:table_name=)
          return klass unless audited_options && audited_options[:table_name]

          klass.table_name = audited_options[:table_name].to_s
          klass
        end

        def register_audit_column_mappings_from_destination(audit_klass)
          return unless audit_klass.respond_to?(:audit_column_for)

          %i[action changes context comment version user auditable associated remote_address request_uuid].each do |concept|
            column = audit_klass.audit_column_for(concept)
            next if column.nil?
            ActiveVersion.column_mapper.register(self, :audits, concept, column)
          end
        end

        def infer_audit_storage_and_columns(audit_klass, options)
          inferred = options.dup
          changes_column = ActiveVersion.column_mapper.column_for(self, :audits, :changes).to_s

          begin
            explicit_storage = if audit_klass.respond_to?(:active_version_audit_schema)
              (audit_klass.active_version_audit_schema || {})[:storage]
            end
            inferred[:storage] ||= explicit_storage&.to_sym
            inferred[:storage] ||= audit_klass.column_names.include?(changes_column) ? ActiveVersion.config.audit_storage : :mirror_columns

            if inferred[:storage].to_sym == :mirror_columns && inferred[:only].nil?
              inferred[:only] = infer_table_audited_columns(audit_klass)
            else
              inferred[:only] ||= []
            end
          rescue ActiveRecord::ConnectionNotDefined, ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            inferred[:storage] ||= ActiveVersion.config.audit_storage
            inferred[:only] ||= []
          end

          inferred
        end

        def infer_table_audited_columns(audit_klass)
          model_columns = column_names.map(&:to_s)
          audit_columns = audit_klass.column_names.map(&:to_s)
          intersection = model_columns & audit_columns

          metadata_columns = [
            "id", "created_at", "updated_at",
            inheritance_column.to_s,
            primary_key.to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :changes).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :context).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :action).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :version).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :comment).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :request_uuid).to_s,
            ActiveVersion.column_mapper.column_for(self, :audits, :remote_address).to_s
          ]

          intersection - metadata_columns - ActiveVersion.config.ignored_attributes.map(&:to_s)
        end

        # Manual callback installation methods
        def audit_on_create
          after_create :audit_create
        end

        def audit_on_update
          before_update :audit_update, if: :should_audit?, prepend: true
        end

        def audit_on_destroy
          before_destroy :audit_destroy, if: :should_audit?
        end

        def audit_on_touch
          after_touch :audit_touch if ::ActiveRecord::VERSION::MAJOR >= 6
        end

        public :audit_on_create, :audit_on_update, :audit_on_destroy, :audit_on_touch

        def revision_with(attributes, id: nil)
          # Create a new instance with reconstructed attributes
          # This ensures we start with a clean slate
          attrs_to_assign = attributes.except(:audit_version).stringify_keys

          # Filter out deleted columns
          attrs_to_assign.slice!(*column_names)

          revision = new
          revision.assign_attributes(attrs_to_assign)

          # Set id and persisted state after attributes are set
          revision.id = id if id
          revision.instance_variable_set(:@new_record, false)
          revision.instance_variable_set(:@persisted, true)

          # Mark as readonly to prevent database reads and ensure attributes stay in memory
          revision.readonly!

          # Ensure attributes are in the @attributes hash and not being read from DB
          # Clear any cached values that might trigger database reads
          revision.instance_variable_set(:@attributes_cache, {})
          revision.clear_changes_information

          # Clear association proxies to prevent stale references
          clear_association_proxies(revision)

          revision
        end
        public :revision_with

        def clear_association_proxies(revision)
          revision.instance_variables.each do |ivar|
            proxy = revision.instance_variable_get(ivar)
            if !proxy.nil? && proxy.respond_to?(:proxy_respond_to?)
              revision.instance_variable_set(ivar, nil)
            end
          end
        end
      end

      # Get revision at specific version (from audits)
      # This method is separate from HasRevisions#revision to avoid conflicts
      def audit_revision(version: nil)
        return nil unless version

        # Get all audits up to and including the specified version
        version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
        audits_list = audits.where("#{version_column} <= ?", version).order(version_column => :asc).to_a
        return nil if audits_list.empty?

        self.class.revision_with audit_class.reconstruct_attributes(audits_list), id: id
      end

      # Get revision at specific time (from audits)
      # This method is separate from HasRevisions#revision_at to avoid conflicts
      def audit_revision_at(date_or_time)
        time_obj = ActiveVersion.parse_time_to_time(date_or_time)
        # Always raise error for future times
        raise ActiveVersion::FutureTimeError, "Future state cannot be known" if time_obj.future?

        version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
        audits_list = audits.up_until(time_obj).order(version_column => :asc).to_a
        # If no audits found for the time, return the earliest audit if it exists (for times before creation)
        if audits_list.empty?
          earliest_audit = audits.order(version_column => :asc).first
          return nil unless earliest_audit
          audits_list = [earliest_audit]
        end

        self.class.revision_with audit_class.reconstruct_attributes(audits_list), id: id
      end

      # Generate SQL for single audit insert
      def audit_sql(destroy: false)
        # Allow SQL generation even if no changes (for testing/documentation purposes)
        # In production, this would typically only be called when there are changes

        action = if new_record?
          "create"
        elsif destroy
          "destroy"
        else
          "update"
        end

        attrs = {
          action: action,
          audited_changes: audited_changes,
          comment: audit_comment
        }
        attrs[:associated] = send(audit_associated_with) unless audit_associated_with.nil?

        # Build attributes for SQL generation (avoid dangerous attribute error)
        changes_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :changes)
        context_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :context)
        auditable_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :auditable)
        version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
        comment_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :comment)

        # Build changes hash manually to avoid dangerous attribute error
        changes = {
          action: attrs[:action]
        }
        if audit_class.column_names.include?(changes_column.to_s)
          changes[changes_column] = attrs[:audited_changes]
        elsif audited_options[:storage].to_sym == :mirror_columns
          audited_attributes.each do |attr, value|
            next unless audit_class.column_names.include?(attr.to_s)

            changes[attr.to_sym] = value
          end
        end
        changes[comment_column] = attrs[:comment] if attrs[:comment].present?
        changes[context_column] = attrs[:audited_context] if attrs[:audited_context].present?
        changes.merge!(active_version_audit_identity_map)
        changes["#{auditable_column}_type"] = self.class.name
        changes[version_column] = (attrs[:action] == "create") ? 1 : (audits.maximum(version_column) || 0) + 1
        changes[:created_at] = Time.current
        changes[:updated_at] = Time.current

        # Prepare SQL-safe values
        changes = prepare_sql_values(changes)
        changes["created_at"] ||= Time.current

        # Build SQL using Arel
        stmt = Arel::InsertManager.new
        table = Arel::Table.new(audit_class.table_name)
        stmt.into(table)
        changes.keys.each { |key| stmt.columns << table[key] }
        stmt.values = stmt.create_values(changes.values)
        sql = stmt.to_sql

        # Instrument SQL generation
        ActiveVersion::Instrumentation.instrument_audit_sql_generated(self, sql)

        sql
      end

      # Get own and associated audits
      def own_and_associated_audits
        audit_class.unscoped.where(auditable: self)
          .or(audit_class.unscoped.where(associated: self))
          .order(created_at: :desc)
      end

      # Temporarily disable auditing
      def without_auditing(&block)
        self.class.without_auditing(&block)
      end

      # Temporarily enable auditing
      def with_auditing(&block)
        self.class.with_auditing(&block)
      end

      private

      def presence_of_audit_comment
        if comment_required_state?
          errors.add(:audit_comment, :blank) if audit_comment.blank?
        end
      end

      def comment_required_state?
        auditing_enabled &&
          audited_changes.present? &&
          ((audited_options[:on].include?(:create) && new_record?) ||
          (audited_options[:on].include?(:update) && persisted? && changed?))
      end

      def require_comment
        if auditing_enabled && audit_comment.blank?
          errors.add(:audit_comment, :blank)
          throw(:abort)
        end
      end

      public

      def should_audit?
        # Check class-level enabled state
        return false unless self.class.class_auditing_enabled?

        # Check global enabled state
        return false unless ActiveVersion.auditing_enabled

        # Check if/unless conditions
        return false unless run_conditional_check(audited_options[:if])
        return false unless run_conditional_check(audited_options[:unless], matching: false)

        true
      end

      def auditing_enabled
        should_audit?
      end

      def clear_rolled_back_audits
        audits.reset
      end

      # Override audits method to handle dynamically created classes
      # Uses class_name from options if provided
      # Returns standard ActiveRecord relation
      # Use active_audits for filtered results
      def audits
        # Use class_name from options if provided (for dynamically created classes)
        auditable_type = audited_options[:class_name] || self.class.name
        if auditable_type.nil?
          raise ConfigurationError, "Cannot determine class name for dynamically created class. Please specify class_name option in has_audits (e.g., has_audits as: PostAudit, class_name: 'Post')"
        end

        # If class_name is different from actual class name, query directly
        uses_custom_auditable_id = audited_options[:identity_resolver].present? ||
          Array(active_version_audit_identity_columns).length > 1
        if auditable_type != self.class.name || uses_custom_auditable_id
          auditable_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :auditable)
          version_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :version)
          self.class.audit_class.where({"#{auditable_column}_type" => auditable_type}.merge(active_version_audit_identity_map))
            .order(version_column => :asc)
        else
          # Use normal association for classes with proper names
          super
        end
      end

      def active_version_auditable_id_value
        values = active_version_audit_identity_values
        return values.values.first if values.is_a?(Hash) && values.size == 1
        return values.first if values.is_a?(Array) && values.size == 1

        values
      end

      def active_version_audit_identity_columns
        auditable_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :auditable).to_s
        configured = self.class.audited_options && self.class.audited_options[:identity_columns]
        Array(configured.presence || "#{auditable_column}_id").map(&:to_s)
      end

      def active_version_audit_identity_map
        columns = active_version_audit_identity_columns
        values = active_version_audit_identity_values

        case values
        when Hash
          values.transform_keys(&:to_s).slice(*columns)
        when Array
          columns.zip(values).to_h
        else
          {columns.first => values}
        end
      end

      def active_version_audit_identity_values
        resolver = self.class.audited_options && self.class.audited_options[:identity_resolver]
        return default_audit_identity_values if resolver.nil?

        case resolver
        when Proc
          resolver.arity.zero? ? instance_exec(&resolver) : resolver.call(self)
        when Array
          resolver.map { |column| public_send(column) }
        else
          public_send(resolver)
        end
      end

      def default_audit_identity_values
        columns = active_version_audit_identity_columns
        return id if columns.one?

        Array(self.class.primary_key).map { |column| self[column] }
      end

      # Get active audits (excludes combined ones - those with empty changes)
      # Filters in Ruby for database-agnostic behavior
      def active_audits
        changes_column = ActiveVersion.column_mapper.column_for(self.class, :audits, :changes)
        return audits.to_a unless audit_class.column_names.include?(changes_column.to_s)

        audits.to_a.reject do |audit|
          # Check raw column value first (before JSON parsing)
          # Combined audits have their changes set to "{}" (empty JSON object as string)
          raw_changes = audit.read_attribute(changes_column)

          # If raw value is "{}", it's a combined audit
          if raw_changes.is_a?(String) && raw_changes.strip == "{}"
            true
          else
            # Otherwise check parsed value
            changes = audit.audited_changes
            changes.nil? || (changes.is_a?(Hash) && changes.empty?) || (changes.is_a?(String) && changes.strip.empty?)
          end
        end
      end

      def run_conditional_check(condition, matching: true)
        return true if condition.blank?
        return condition.call(self) == matching if condition.respond_to?(:call)
        return send(condition) == matching if respond_to?(condition.to_sym, true)

        true
      end

      def revision_with(attributes)
        # Create a new instance with reconstructed attributes
        # Keep it as a new record to prevent database reads
        attrs_to_assign = attributes.except(:audit_version).stringify_keys
        revision = self.class.new(attrs_to_assign)

        # Set id but keep as new_record to prevent database reads
        revision.id = id
        revision.instance_variable_set(:@new_record, true)
        revision.instance_variable_set(:@persisted, false)

        # Mark as readonly to prevent modifications
        revision.readonly!

        revision
      end
    end
  end
end
