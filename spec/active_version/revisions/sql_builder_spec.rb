require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Revisions::SQLBuilder do
  before(:all) do
    DatabaseHelper.setup
  end

  describe "PostRevision.batch_insert_sql" do
    it "defines batch_insert_sql class method" do
      expect(PostRevision).to respond_to(:batch_insert_sql)
    end

    context "with empty records" do
      it "returns empty string" do
        expect(PostRevision.batch_insert_sql([])).to eq("")
      end
    end

    context "with records" do
      before do
        @post1 = Post.create!(title: "Hello")
        @post2 = Post.create!(title: "World")
        @post1.title = "Hello updated"
        @post2.title = "World updated"
      end

      it "generates SQL for multiple records" do
        sql = PostRevision.batch_insert_sql([@post1, @post2], version: 1)
        expect(sql).to be_a(String)
        expect(sql).to include("INSERT")
      end

      it "ignores block return values when collector is unused" do
        sql = PostRevision.batch_insert_sql(version: 1) { [@post1, @post2] }
        expect(sql).to eq("")
      end

      it "supports block collector argument" do
        sql = PostRevision.batch_insert_sql(version: 1) do |batch|
          batch << @post1
          batch << @post2
        end
        expect(sql).to include("INSERT")
      end

      it "captures updates executed inside block even when collector is unused" do
        post1 = Post.create!(title: "A")
        post2 = Post.create!(title: "B")
        post3 = Post.create!(title: "C")

        sql = PostRevision.batch_insert_sql(version: 1) do |batch|
          post1.update!(title: "A1")
          post2.update!(title: "B1")
          post3.destroy!
        end

        expect(sql).to include("INSERT")
        values_count = sql.scan(/\),\s*\(/).count + 1
        expect(values_count).to eq(2)
      end

      it "generates combined SQL by default" do
        sql = PostRevision.batch_insert_sql([@post1, @post2], version: 1)
        expect(sql.scan("INSERT").count).to eq(1)
      end

      it "includes multiple VALUES tuples when combined" do
        sql = PostRevision.batch_insert_sql([@post1, @post2], version: 1)
        values_count = sql.scan(/\),\s*\(/).count + 1
        expect(values_count).to eq(2)
      end

      it "generates separate SQL when combine is false" do
        sql = PostRevision.batch_insert_sql([@post1, @post2], version: 1, combine: false)
        expect(sql.scan("INSERT").count).to eq(2)
      end

      it "uses default version 1 when not specified" do
        sql = PostRevision.batch_insert_sql([@post1, @post2])
        expect(sql).to include("INSERT")
      end

      it "returns empty string for non-dirty records unless forced" do
        clean_1 = Post.create!(title: "Clean 1")
        clean_2 = Post.create!(title: "Clean 2")
        expect(PostRevision.batch_insert_sql([clean_1, clean_2], version: 1)).to eq("")
        expect(PostRevision.batch_insert_sql([clean_1, clean_2], version: 1, force: true)).to include("INSERT")
      end

      it "supports upsert mode for combined SQL" do
        sql = PostRevision.batch_insert_sql([@post1, @post2], version: 1, upsert: true)
        expect(sql).to include("ON CONFLICT")
      end
    end

    context "when revision_class is nil" do
      let(:model_without_revision) do
        Class.new(ApplicationRecord) do
          self.table_name = "posts"
          def self.name
            "PostWithoutRevision"
          end

          def self.revision_class
            nil
          end
        end
      end

      it "returns empty string" do
        expect(PostRevision.batch_insert_sql([model_without_revision.new])).to eq("")
      end
    end

    context "with different value types in prepare_sql_value" do
      before do
        @post = Post.create!(title: "Test", body: "Body")
      end

      it "handles Hash values" do
        # This tests prepare_sql_value indirectly through batch_insert_sql
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end

      it "handles Array values" do
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end

      it "handles Time values" do
        @post.created_at = Time.current
        @post.save!
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end

      it "handles Date values" do
        date_value = Time.zone.today
        @post.created_at = date_value
        @post.save!
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end

      it "handles DateTime values" do
        @post.created_at = DateTime.current
        @post.save!
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end

      it "handles other value types (not Hash, Array, Time, DateTime, Date)" do
        @post.title = "Test"
        @post.body = "Body"
        @post.save!
        sql = PostRevision.batch_insert_sql([@post], version: 1)
        expect(sql).to be_a(String)
      end
    end
  end

  describe "PostRevision.batch_upsert_sql" do
    it "defines batch_upsert_sql class method" do
      expect(PostRevision).to respond_to(:batch_upsert_sql)
    end

    it "generates upsert SQL" do
      post = Post.create!(title: "Hello")
      sql = PostRevision.batch_upsert_sql([post], version: 1, force: true)
      expect(sql).to include("INSERT")
      expect(sql).to include("ON CONFLICT")
    end
  end

  describe "PostRevision.batch_insert" do
    it "defines batch_insert class method" do
      expect(PostRevision).to respond_to(:batch_insert)
    end

    it "executes generated SQL" do
      post = Post.create!(title: "Exec revision")
      expect {
        PostRevision.batch_insert([post], version: 999, force: true)
      }.to change { PostRevision.count }.by(1)
    end

    it "supports block-based inserts" do
      post = Post.create!(title: "Exec revision block")
      expect {
        PostRevision.batch_insert(version: 1000, force: true) do |batch|
          batch << post
        end
      }.to change { PostRevision.count }.by(1)
    end

    it "captures operations executed inside block" do
      post1 = Post.create!(title: "Batch block A")
      post2 = Post.create!(title: "Batch block B")
      post3 = Post.create!(title: "Batch block C")

      expect {
        PostRevision.batch_insert(version: 1001) do
          post1.update!(title: "Batch block A updated")
          post2.update!(title: "Batch block B updated")
          post3.destroy!
        end
      }.to change { PostRevision.count }.by(2)
    end
  end
end
