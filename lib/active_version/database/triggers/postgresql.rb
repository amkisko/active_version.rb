module ActiveVersion
  module Database
    module Triggers
      # PostgreSQL trigger support for ActiveVersion
      module PostgreSQL
        class << self
          # Generate trigger function for audits
          # @param table_name [String] Name of the table to create trigger for
          # @param audit_table_name [String] Name of the audit table
          # @param options [Hash] Trigger options
          # @return [String] SQL for trigger function
          def generate_audit_trigger_function(table_name, audit_table_name, options = {})
            function_name = "active_version_audit_#{table_name}"
            auditable_type = options[:auditable_type] || table_name.classify
            version_column = options[:version_column] || "version"
            changes_column = options[:changes_column] || "audited_changes"
            context_column = options[:context_column] || "audited_context"
            action_column = options[:action_column] || "action"

            <<~SQL
              CREATE OR REPLACE FUNCTION #{function_name}()
              RETURNS TRIGGER AS $$
              DECLARE
                new_version INTEGER;
                changes JSONB;
                context_data JSONB;
                action_type TEXT;
              BEGIN
                -- Determine action
                IF TG_OP = 'INSERT' THEN
                  action_type := 'create';
                  changes := to_jsonb(NEW.*);
                ELSIF TG_OP = 'UPDATE' THEN
                  action_type := 'update';
                  changes := jsonb_build_object(
                    'old', to_jsonb(OLD.*),
                    'new', to_jsonb(NEW.*)
                  );
                ELSIF TG_OP = 'DELETE' THEN
                  action_type := 'destroy';
                  changes := to_jsonb(OLD.*);
                END IF;

                -- Get version number
                IF action_type = 'create' THEN
                  new_version := 1;
                ELSE
                  SELECT COALESCE(MAX(#{version_column}), 0) + 1
                  INTO new_version
                  FROM #{audit_table_name}
                  WHERE #{audit_table_name}.auditable_id = COALESCE(NEW.id, OLD.id)
                    AND #{audit_table_name}.auditable_type = '#{auditable_type}';
                END IF;

                -- Get context from session variables (if set)
                context_data := COALESCE(
                  current_setting('active_version.context', true)::jsonb,
                  '{}'::jsonb
                );

                -- Insert audit record
                IF TG_OP = 'DELETE' THEN
                  INSERT INTO #{audit_table_name} (
                    auditable_id,
                    auditable_type,
                    #{action_column},
                    #{changes_column},
                    #{version_column},
                    #{context_column},
                    created_at,
                    updated_at
                  ) VALUES (
                    OLD.id,
                    '#{auditable_type}',
                    action_type,
                    changes,
                    new_version,
                    context_data,
                    NOW(),
                    NOW()
                  );
                  RETURN OLD;
                ELSE
                  INSERT INTO #{audit_table_name} (
                    auditable_id,
                    auditable_type,
                    #{action_column},
                    #{changes_column},
                    #{version_column},
                    #{context_column},
                    created_at,
                    updated_at
                  ) VALUES (
                    NEW.id,
                    '#{auditable_type}',
                    action_type,
                    changes,
                    new_version,
                    context_data,
                    NOW(),
                    NOW()
                  );
                  RETURN NEW;
                END IF;
              END;
              $$ LANGUAGE plpgsql;
            SQL
          end

          # Generate trigger for audits
          # @param table_name [String] Name of the table
          # @param options [Hash] Trigger options
          # @return [String] SQL for CREATE TRIGGER statement
          def generate_audit_trigger(table_name, options = {})
            function_name = "active_version_audit_#{table_name}"
            trigger_name = options[:trigger_name] || "active_version_audit_on_#{table_name}"
            events = options[:events] || [:insert, :update, :delete]

            event_clause = events.map(&:upcase).join(" OR ")

            <<~SQL
              CREATE TRIGGER #{trigger_name}
              AFTER #{event_clause} ON #{table_name}
              FOR EACH ROW
              WHEN (coalesce(current_setting('active_version.disabled', true), '') <> 'on')
              EXECUTE FUNCTION #{function_name}();
            SQL
          end

          # Generate trigger function for revisions
          # @param table_name [String] Name of the table
          # @param revision_table_name [String] Name of the revision table
          # @param options [Hash] Trigger options
          # @return [String] SQL for trigger function
          def generate_revision_trigger_function(table_name, revision_table_name, options = {})
            function_name = "active_version_revision_#{table_name}"
            foreign_key = options[:foreign_key] || "#{table_name.singularize}_id"
            version_column = options[:version_column] || "version"

            <<~SQL
              CREATE OR REPLACE FUNCTION #{function_name}()
              RETURNS TRIGGER AS $$
              DECLARE
                new_version INTEGER;
                revision_data RECORD;
              BEGIN
                -- Only create revision on UPDATE
                IF TG_OP != 'UPDATE' THEN
                  RETURN NEW;
                END IF;

                -- Skip if nothing changed
                IF NEW.* IS NOT DISTINCT FROM OLD.* THEN
                  RETURN NEW;
                END IF;

                -- Get next version number
                SELECT COALESCE(MAX(#{version_column}), 0) + 1
                INTO new_version
                FROM #{revision_table_name}
                WHERE #{revision_table_name}.#{foreign_key} = NEW.id;

                -- Create revision with OLD values
                INSERT INTO #{revision_table_name} (
                  #{foreign_key},
                  #{version_column},
                  #{build_revision_columns(table_name, options)},
                  created_at,
                  updated_at
                )
                SELECT
                  NEW.id,
                  new_version,
                  #{build_revision_values("OLD", table_name, options)},
                  NOW(),
                  NOW();

                RETURN NEW;
              END;
              $$ LANGUAGE plpgsql;
            SQL
          end

          # Generate trigger for revisions
          # @param table_name [String] Name of the table
          # @param options [Hash] Trigger options
          # @return [String] SQL for CREATE TRIGGER statement
          def generate_revision_trigger(table_name, options = {})
            function_name = "active_version_revision_#{table_name}"
            trigger_name = options[:trigger_name] || "active_version_revision_on_#{table_name}"

            <<~SQL
              CREATE TRIGGER #{trigger_name}
              BEFORE UPDATE ON #{table_name}
              FOR EACH ROW
              WHEN (coalesce(current_setting('active_version.disabled', true), '') <> 'on')
              EXECUTE FUNCTION #{function_name}();
            SQL
          end

          # Drop trigger function
          # @param function_name [String] Name of the function
          # @return [String] SQL for DROP FUNCTION statement
          def drop_trigger_function(function_name)
            "DROP FUNCTION IF EXISTS #{function_name}() CASCADE;"
          end

          # Drop trigger
          # @param trigger_name [String] Name of the trigger
          # @param table_name [String] Name of the table
          # @return [String] SQL for DROP TRIGGER statement
          def drop_trigger(trigger_name, table_name)
            "DROP TRIGGER IF EXISTS #{trigger_name} ON #{table_name} CASCADE;"
          end

          private

          def build_revision_columns(table_name, options)
            columns = normalize_revision_columns(options)
            columns.join(", ")
          end

          def build_revision_values(record_prefix, table_name, options)
            columns = normalize_revision_columns(options)
            columns.map { |column| "#{record_prefix}.#{column}" }.join(", ")
          end

          def normalize_revision_columns(options)
            raw_columns = Array(options[:columns]).map(&:to_s)
            if raw_columns.empty?
              raise ArgumentError, "revision trigger generation requires :columns option"
            end

            foreign_key = options[:foreign_key].to_s
            version_column = options[:version_column].to_s
            metadata_columns = [foreign_key, version_column, "id", "created_at", "updated_at"]
            raw_columns.reject { |col| metadata_columns.include?(col) }
          end
        end
      end
    end
  end
end
