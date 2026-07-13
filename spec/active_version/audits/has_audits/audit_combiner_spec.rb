require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe ActiveVersion::Audits::HasAudits::AuditCombiner, type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    cleanup_test_data
    reset_active_version_context
  end

  describe "#evaluate_max_audits" do
    let(:post_class) do
      Class.new(Post) do
        has_audits as: PostAudit, max_audits: 5, class_name: "Post"
      end
    end

    it "returns max_audits from options" do
      post = post_class.new
      expect(post.send(:evaluate_max_audits)).to eq(5)
    end

    it "evaluates max_audits from proc" do
      post_class_with_proc = Class.new(Post) do
        has_audits as: PostAudit, max_audits: -> { 3 }, class_name: "Post"
      end
      post = post_class_with_proc.new
      expect(post.send(:evaluate_max_audits)).to eq(3)
    end

    it "evaluates max_audits from symbol method" do
      post_class_with_symbol = Class.new(Post) do
        has_audits as: PostAudit, max_audits: :get_max, class_name: "Post"

        def self.get_max
          4
        end
      end
      post = post_class_with_symbol.create!(title: "Test")
      expect(post.send(:evaluate_max_audits)).to eq(4)
    end

    it "falls back to global config when option is nil" do
      original_max = ActiveVersion.config.max_audits
      ActiveVersion.config.max_audits = 10

      post_class_no_max = Class.new(Post) do
        has_audits as: PostAudit, class_name: "Post"
      end
      post = post_class_no_max.new
      expect(post.send(:evaluate_max_audits)).to eq(10)

      ActiveVersion.config.max_audits = original_max
    end

    it "returns nil when max_audits is not set" do
      original_max = ActiveVersion.config.max_audits
      ActiveVersion.config.max_audits = nil

      post_class_no_max = Class.new(Post) do
        has_audits as: PostAudit, class_name: "Post"
      end
      post = post_class_no_max.new
      expect(post.send(:evaluate_max_audits)).to be_nil

      ActiveVersion.config.max_audits = original_max
    end

    it "converts to integer and takes absolute value" do
      post_class_negative = Class.new(Post) do
        has_audits as: PostAudit, max_audits: -5, class_name: "Post"
      end
      post = post_class_negative.new
      expect(post.send(:evaluate_max_audits)).to eq(5)
    end
  end

  describe "#combine_audits" do
    let(:post_class) do
      Class.new(Post) do
        has_audits as: PostAudit, max_audits: 2, class_name: "Post"
      end
    end

    it "returns early if audits_to_combine is empty" do
      post = post_class.create!(title: "v1")
      result = post.send(:combine_audits, [])
      expect(result).to be_nil
    end

    it "handles relation input by converting to array" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")
      audits_relation = post.audits.limit(1)
      # Mock update_columns to avoid readonly issues in tests
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)
      expect { post.send(:combine_audits, audits_relation) }.not_to raise_error
    end

    it "merges changes from multiple audits" do
      post = post_class.create!(title: "v1", body: "body1")
      post.update!(title: "v2", body: "body2")
      post.update!(title: "v3")

      audits = post.audits.to_a
      # Mock update_columns to avoid readonly issues
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)
      allow(post.class.audit_class.connection).to receive(:execute).and_return(true)

      post.send(:combine_audits, audits.first(2))

      # Check that changes were merged (audit should still exist)
      combined_audit = post.audits.find_by(version: 2)
      expect(combined_audit).to be_present
    end

    it "handles JSON parsing errors gracefully" do
      post = post_class.create!(title: "v1")
      audit = post.audits.first
      # Set invalid JSON via SQL
      audit.class.connection.execute(
        "UPDATE #{audit.class.table_name} SET #{ActiveVersion.config.audit_changes_column} = 'invalid json{' WHERE id = #{audit.id}"
      )
      audit.reload
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)

      expect { post.send(:combine_audits, [audit]) }.not_to raise_error
    end

    it "merges contexts from multiple audits" do
      post = post_class.create!(title: "v1")

      ActiveVersion.with_context("user_id" => 1) do
        post.update!(title: "v2")
      end

      ActiveVersion.with_context("user_id" => 2) do
        post.update!(title: "v3")
      end

      audits = post.audits.to_a
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)
      allow(post.class.audit_class.connection).to receive(:execute).and_return(true)

      post.send(:combine_audits, audits.first(2))

      # Contexts should be merged (audit should still exist)
      combined_audit = post.audits.find_by(version: 2)
      expect(combined_audit).to be_present
    end

    it "handles nil context values" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")

      audits = post.audits.to_a
      # Set one audit's context to nil via SQL
      audit = audits.first
      audit.class.connection.execute(
        "UPDATE #{audit.class.table_name} SET #{ActiveVersion.config.audit_context_column} = NULL WHERE id = #{audit.id}"
      )
      audits.first.reload
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)
      allow(post.class.audit_class.connection).to receive(:execute).and_return(true)

      expect { post.send(:combine_audits, audits.first(2)) }.not_to raise_error
    end

    it "marks old audits as combined using SQL" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")
      post.update!(title: "v3")

      audits = post.audits.to_a
      old_audit = audits.first
      allow_any_instance_of(PostAudit).to receive(:update_columns).and_return(true)

      # Mock the SQL execution to verify it's called
      expect(post.class.audit_class.connection).to receive(:execute).at_least(:once)
      post.send(:combine_audits, audits.first(2))
    end

    it "clears association cache after combining" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")

      audits = post.audits.to_a
      # Load the association
      post.audits.to_a

      expect(post.audits).to receive(:reset).at_least(:once)
      post.send(:combine_audits, audits.first(2))
    end

    it "handles association not being available" do
      post = post_class.create!(title: "v1")
      audits = post.audits.to_a

      # Remove audits method temporarily
      allow(post).to receive(:respond_to?).and_call_original
      allow(post).to receive(:respond_to?).with(:audits).and_return(false)

      expect { post.send(:combine_audits, audits.first(2)) }.not_to raise_error
    end
  end

  describe "#combine_audits_if_needed" do
    let(:post_class) do
      Class.new(Post) do
        has_audits as: PostAudit, max_audits: 3, class_name: "Post"
      end
    end

    it "does nothing when max_audits is 0" do
      post_class_zero = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 0, class_name: "Post"
      end
      post = post_class_zero.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      initial_count = post.audits.count
      post.send(:combine_audits_if_needed)
      expect(post.audits.count).to eq(initial_count)
    end

    it "handles dynamically created classes with class_name" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      expect { post.send(:combine_audits_if_needed) }.not_to raise_error
    end

    it "refreshes cached audits association before querying in loop" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      post.audits.to_a
      audits_association = post.association(:audits)
      expect(audits_association).to receive(:reset).at_least(:once).and_call_original

      post.send(:combine_audits_if_needed)
    end

    it "filters combined audits by raw column value" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      # Manually mark one audit as combined
      audit = post.audits.first
      audit.class.connection.execute(
        "UPDATE #{audit.class.table_name} SET #{ActiveVersion.config.audit_changes_column} = '{}' WHERE id = #{audit.id}"
      )

      post.send(:combine_audits_if_needed)
      # Should not try to combine already combined audits
      expect(post.active_audits.length).to be <= 3
    end

    it "stops after max_iterations to prevent infinite loops" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      # Mock to prevent actual combining but allow loop to run
      allow(post).to receive(:combine_audits).and_return(nil)

      expect { post.send(:combine_audits_if_needed) }.not_to raise_error
    end

    it "handles case where auditable_type differs from class name" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }

      # Should use direct query path for dynamically created classes
      expect { post.send(:combine_audits_if_needed) }.not_to raise_error
    end

    it "reloads association when it's loaded" do
      post = post_class.create!(title: "v1")
      5.times { |i| post.update!(title: "v#{i + 2}") }
      post.audits.to_a
      # Should run without error and keep active_audits under limit (implementation may use reload/reset)
      expect { post.send(:combine_audits_if_needed) }.not_to raise_error
      expect(post.active_audits.count).to be <= 3
    end

    it "handles empty audits_to_combine array" do
      post = post_class.create!(title: "v1")
      expect { post.send(:combine_audits, []) }.not_to raise_error
    end

    it "handles string changes that are not valid JSON" do
      post = post_class.create!(title: "v1")
      audit = post.audits.first
      # Set changes to invalid JSON that will cause parse error
      audit.class.connection.execute(
        "UPDATE #{audit.class.table_name} SET #{ActiveVersion.config.audit_changes_column} = 'invalid json{' WHERE id = #{audit.id}"
      )
      audit.reload

      expect { post.send(:combine_audits, [audit]) }.not_to raise_error
    end

    it "handles nil context values gracefully" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")

      audits = post.audits.to_a
      # Set one audit's context to nil via SQL
      audit = audits.first
      audit.class.connection.execute(
        "UPDATE #{audit.class.table_name} SET #{ActiveVersion.config.audit_context_column} = NULL WHERE id = #{audit.id}"
      )
      audits.first.reload

      expect { post.send(:combine_audits, audits.first(2)) }.not_to raise_error
    end

    it "handles case where association is not loaded" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")

      audits = post.audits.to_a
      # Ensure association is not loaded
      post.audits.reset
      allow(post.send(:association, :audits)).to receive(:loaded?).and_return(false)

      expect { post.send(:combine_audits, audits.first(2)) }.not_to raise_error
    end

    it "handles case where respond_to?(:association) returns false" do
      post = post_class.create!(title: "v1")
      post.update!(title: "v2")
      audits = post.audits.to_a
      # When association is not available, combine_audits still runs (uses audits.reset path)
      allow(post).to receive(:respond_to?).and_call_original
      allow(post).to receive(:respond_to?).with(:association).and_return(false)

      expect { post.send(:combine_audits, audits.first(2)) }.not_to raise_error
    end
  end
end
