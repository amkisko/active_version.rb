require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "Continued coverage (change filters + edge paths)" do
  before(:all) do
    DatabaseHelper.setup
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    ActiveVersion.clear_context!
    ActiveVersion.auditing_enabled = true
  end

  describe "HasAudits::ChangeFilters" do
    it "uses changes_to_save when for_touch is true" do
      post = Post.create!(title: "touch")
      next unless post.respond_to?(:changes_to_save)

      allow(post).to receive(:changes_to_save).and_return({"title" => %w[touch touched]})
      ch = post.send(:audited_changes, for_touch: true)
      expect(ch).to have_key("title")
    end

    it "includes except columns in non_audited_columns" do
      klass = Class.new(ApplicationRecord) do
        self.table_name = "posts"
        include ActiveVersion::Audits::HasAudits

        has_audits as: PostAudit, class_name: "Post", except: [:title]
      end

      p = klass.new(title: "x", body: "body")
      expect(p.send(:non_audited_columns)).to include("title")
    end

    it "maps enum keys when store_synthesized_enums is false (array branch)" do
      allow(ActiveVersion.config).to receive(:store_synthesized_enums).and_return(false)
      post = Post.create!(title: "enum")
      allow(Post).to receive(:defined_enums).and_return({"status" => {"draft" => 0, "live" => 1}})

      h = {"status" => %w[draft live]}
      out = post.send(:normalize_enum_changes, h.dup)
      expect(out["status"]).to eq([0, 1])
    end

    it "maps enum keys when store_synthesized_enums is false (scalar branch)" do
      allow(ActiveVersion.config).to receive(:store_synthesized_enums).and_return(false)
      post = Post.create!(title: "enum2")
      allow(Post).to receive(:defined_enums).and_return({"status" => {"draft" => 0, "live" => 1}})

      h = {"status" => "draft"}
      out = post.send(:normalize_enum_changes, h.dup)
      expect(out["status"]).to eq(0)
    end

    it "redacts a non-array audited change value" do
      post = Post.create!(title: "red")
      audited = {"title" => "secret"}
      out = post.send(:filter_attr_values, audited_changes: audited, attrs: ["title"], placeholder: "X")
      expect(out["title"]).to eq("X")
    end
  end
end
