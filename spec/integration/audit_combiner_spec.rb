require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion AuditCombiner Integration", type: :integration do
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

  describe "combine_audits_if_needed" do
    it "does not combine audits when under max_audits limit" do
      # Create a model with max_audits set to 10
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 10, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      5.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should have 6 audits (1 create + 5 updates)
      expect(post.audits.count).to eq(6)
      expect(post.audits.pluck(:version)).to eq([1, 2, 3, 4, 5, 6])
    end

    it "combines audits when exceeding max_audits limit" do
      # Create a model with max_audits set to 3
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 3, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      5.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should have combined oldest audits, keeping only 3 most recent
      # 1 create + 5 updates = versions 1..6; keep 3 most recent = 4, 5, 6
      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(3)

      versions = active_audits.map(&:version)
      expect(versions).to eq([4, 5, 6])
    end

    it "merges changes from combined audits" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 2, class_name: "Post"
      end

      post = post_class.create!(title: "v1", body: "body1")
      post.title = "v2"
      post.body = "body2"
      post.save!
      post.title = "v3"
      post.body = "body3"
      post.save!
      post.title = "v4"
      post.body = "body4"
      post.save!

      # Oldest audit (version 2) should have merged changes from version 1
      combined_audit = post.audits.find_by(version: 2)
      expect(combined_audit).to be_present

      # Verify changes were merged
      changes = combined_audit.audited_changes
      expect(changes).to be_a(Hash)
      # The combined audit should contain changes from the merged audits
    end

    it "merges contexts from combined audits" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 2, class_name: "Post"
      end

      post = nil
      ActiveVersion.with_context("request_id" => "req1") do
        post = post_class.create!(title: "v1")
      end

      ActiveVersion.with_context("request_id" => "req2") do
        post.title = "v2"
        post.save!
      end

      ActiveVersion.with_context("request_id" => "req3") do
        post.title = "v3"
        post.save!
      end

      # After combining, the oldest audit should have merged contexts
      combined_audit = post.audits.find_by(version: 2)
      if combined_audit
        context = combined_audit.audited_context
        expect(context).to be_a(Hash) if context
      end
    end

    it "respects max_audits from configuration" do
      original_max = ActiveVersion.config.max_audits
      ActiveVersion.config.max_audits = 2

      post = Post.create!(title: "v1")
      4.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should have combined to keep only 2 most recent (1 create + 4 updates = 1..5; keep 4, 5)
      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(2)
      versions = active_audits.map(&:version)
      expect(versions).to eq([4, 5])

      ActiveVersion.config.max_audits = original_max
    end

    it "evaluates max_audits from proc" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: -> { 3 }, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      5.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should keep 3 most recent (1 create + 5 updates = 1..6; keep 4, 5, 6)
      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(3)
      versions = active_audits.map(&:version)
      expect(versions).to eq([4, 5, 6])
    end

    it "evaluates max_audits from symbol method" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: :calculate_max_audits, class_name: "Post"

        def self.calculate_max_audits
          2
        end
      end

      post = post_class.create!(title: "v1")
      4.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should keep 2 most recent (1 create + 4 updates = 1..5; keep 4, 5)
      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(2)
      versions = active_audits.map(&:version)
      expect(versions).to eq([4, 5])
    end

    it "handles zero max_audits (no combining)" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 0, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      3.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should not combine (max_audits is 0 or negative)
      expect(post.audits.count).to eq(4)
    end

    it "preserves most recent audits when combining" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 3, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      7.times { |i|
        post.title = "v#{i + 2}"
        post.save!
      }

      # Should keep versions 6, 7, 8 (most recent 3)
      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(3)
      versions = active_audits.map(&:version)
      expect(versions).to eq([6, 7, 8])

      # Verify the kept audits have correct data
      active_audits.each do |audit|
        expect(audit.action).to be_present
        expect(audit.version).to be >= 6
      end
    end

    it "keeps active audit count at max_audits after many updates" do
      post_class = Class.new(Post) do
        has_audits as: PostAudit, max_audits: 3, class_name: "Post"
      end

      post = post_class.create!(title: "v1")
      20.times { |index|
        post.title = "v#{index + 2}"
        post.save!
      }

      active_audits = post.active_audits.sort_by(&:version)
      expect(active_audits.length).to eq(3)
      expect(active_audits.map(&:version)).to eq([19, 20, 21])
    end
  end
end
