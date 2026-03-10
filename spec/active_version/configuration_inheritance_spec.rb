require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "ActiveVersion Configuration Inheritance", type: :integration do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    Thread.current["active_version_Post_audited_options"] = nil
  end

  describe "thread-local configuration" do
    it "merges thread-local options with class-level options" do
      original_only = Post.audited_options[:only]

      Post.with_audited_options(only: ["title"]) do
        expect(Post.audited_options[:only]).to include("title")
      end

      # Should restore original
      expect(Post.audited_options[:only]).to eq(original_only)
    end

    it "thread-local options take precedence" do
      Post.with_audited_options(only: ["title"]) do
        post = Post.create!(title: "Test", body: "Body")
        post.title = "Updated"
        post.body = "Updated Body"
        post.save!

        audit = post.audits.last
        changes = audit.audited_changes
        expect(changes).to have_key("title")
        expect(changes).not_to have_key("body")
      end
    end

    it "isolates configuration per thread" do
      thread1_options = nil
      thread2_options = nil

      thread1 = Thread.new do
        Post.with_audited_options(only: ["title"]) do
          thread1_options = Post.audited_options[:only]
        end
      end

      thread2 = Thread.new do
        Post.with_audited_options(only: ["body"]) do
          thread2_options = Post.audited_options[:only]
        end
      end

      thread1.join
      thread2.join

      expect(thread1_options).to include("title")
      expect(thread2_options).to include("body")
    end

    it "restores configuration after block" do
      original = Post.audited_options.dup

      Post.with_audited_options(max_audits: 5) do
        expect(Post.audited_options[:max_audits]).to eq(5)
      end

      expect(Post.audited_options[:max_audits]).to eq(original[:max_audits])
    end

    it "handles nested with_audited_options" do
      Post.with_audited_options(only: ["title"]) do
        Post.with_audited_options(except: ["body"]) do
          options = Post.audited_options
          expect(options[:only]).to include("title")
          expect(options[:except]).to include("body")
        end
      end
    end
  end
end
