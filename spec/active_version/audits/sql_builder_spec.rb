require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Audits::SQLBuilder do
  before(:all) do
    DatabaseHelper.setup
  end

  describe "PostAudit.batch_insert_sql" do
    it "defines batch_insert_sql class method" do
      expect(PostAudit).to respond_to(:batch_insert_sql)
    end

    context "with empty records" do
      it "returns empty string" do
        expect(PostAudit.batch_insert_sql([])).to eq("")
      end
    end

    context "with records" do
      before do
        @post1 = Post.create!(title: "Hello")
        @post2 = Post.create!(title: "World")
      end

      it "generates SQL for multiple records" do
        sql = PostAudit.batch_insert_sql([@post1, @post2], force: true)
        expect(sql).to be_a(String)
        expect(sql).to include("INSERT")
      end

      it "ignores block return values when collector is unused" do
        sql = PostAudit.batch_insert_sql(force: true) { [@post1, @post2] }
        expect(sql).to eq("")
      end

      it "supports block collector argument" do
        sql = PostAudit.batch_insert_sql(force: true) do |batch|
          batch << @post1
          batch << @post2
        end
        expect(sql).to include("INSERT")
      end

      it "generates combined SQL by default" do
        sql = PostAudit.batch_insert_sql([@post1, @post2], force: true)
        expect(sql.scan("INSERT").count).to eq(1)
      end

      it "includes multiple VALUES tuples when combined" do
        sql = PostAudit.batch_insert_sql([@post1, @post2], force: true)
        values_count = sql.scan(/\),\s*\(/).count + 1
        expect(values_count).to eq(2)
      end

      it "generates separate SQL when combine is false" do
        sql = PostAudit.batch_insert_sql([@post1, @post2], force: true, combine: false)
        expect(sql.scan("INSERT").count).to eq(2)
      end

      it "returns empty string when records haven't changed and force is false" do
        sql = PostAudit.batch_insert_sql([@post1, @post2])
        expect(sql).to eq("")
      end

      it "handles destroy action" do
        sql = PostAudit.batch_insert_sql([@post1], force: true, destroy: true)
        expect(sql).to include("INSERT")
        expect(sql).to include("destroy")
      end

      it "handles allow_saved option" do
        sql = PostAudit.batch_insert_sql([@post1], allow_saved: true)
        expect(sql).to be_a(String)
      end

      it "increments version per auditable within the same batch" do
        sql = PostAudit.batch_insert_sql([@post1, @post1], force: true)
        PostAudit.connection.execute(sql)

        versions = PostAudit
          .where(auditable_type: "Post", auditable_id: @post1.id)
          .order(version: :asc)
          .pluck(:version)

        expect(versions.last(2)).to eq([2, 3])
      end

      it "handles update action (not create or destroy)" do
        @post1.title = "Updated"
        @post1.save!
        sql = PostAudit.batch_insert_sql([@post1], force: true)
        expect(sql).to include("INSERT")
      end

      it "handles context option" do
        sql = PostAudit.batch_insert_sql([@post1], force: true, context: {ip: "127.0.0.1"})
        expect(sql).to include("INSERT")
      end

      it "handles comment" do
        @post1.audit_comment = "Test comment"
        sql = PostAudit.batch_insert_sql([@post1], force: true)
        expect(sql).to include("INSERT")
      end
    end

    context "with different value types in prepare_sql_value" do
      before do
        @post = Post.create!(title: "Test")
      end

      it "handles Hash values" do
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles Array values" do
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles Time values" do
        @post.created_at = Time.current
        @post.save!
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles DateTime values" do
        @post.created_at = DateTime.current
        @post.save!
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles Date values" do
        date_value = Time.zone.today
        @post.created_at = date_value
        @post.save!
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles user with id" do
        user = double("user", id: 1, class: double("UserClass", name: "User"))
        allow(ActiveVersion::RequestStore).to receive(:attributes).and_return({audited_user: user})
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles user without id method" do
        # Create a user object that doesn't respond to :id
        user_class = Class.new do
          def self.name
            "User"
          end
        end
        user = Object.new
        def user.class
          @user_class ||= Class.new do
            def self.name
              "User"
            end
          end
        end

        # Make it not respond to :id
        def user.respond_to?(method, include_private = false)
          return false if method == :id
          super
        end
        allow(ActiveVersion::RequestStore).to receive(:attributes).and_return({audited_user: user})
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles user column that doesn't end with _id" do
        user = double("user", id: 1, class: double("UserClass", name: "User"))
        allow(ActiveVersion::RequestStore).to receive(:attributes).and_return({audited_user: user})
        # Mock column_mapper to return a non-_id column
        allow(ActiveVersion.column_mapper).to receive(:column_for).and_call_original
        allow(ActiveVersion.column_mapper).to receive(:column_for).with(Post, :audits, :user).and_return(:user)
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end

      it "handles other value types (not Hash, Array, Time, DateTime, Date)" do
        @post.title = "Test"
        @post.save!
        sql = PostAudit.batch_insert_sql([@post], force: true)
        expect(sql).to be_a(String)
      end
    end

    context "when audit_class is nil" do
      let(:model_without_audit) do
        Class.new(ApplicationRecord) do
          self.table_name = "posts"
          def self.name
            "PostWithoutAudit"
          end

          def self.audit_class
            nil
          end
        end
      end

      it "returns empty string" do
        expect(PostAudit.batch_insert_sql([model_without_audit.new])).to eq("")
      end
    end

    context "when first_record is nil" do
      it "returns empty string" do
        expect(PostAudit.batch_insert_sql([nil])).to eq("")
      end
    end
  end

  describe "PostAudit.batch_insert" do
    it "defines batch_insert class method" do
      expect(PostAudit).to respond_to(:batch_insert)
    end

    it "captures block writes and inserts once per create" do
      expect {
        PostAudit.batch_insert(force: true) do
          Post.create!(title: "Exec audit block 1")
          Post.create!(title: "Exec audit block 2")
          Post.create!(title: "Exec audit block 3")
        end
      }.to change { PostAudit.count }.by(3)
    end

    it "returns SQL without executing for block capture mode" do
      before_count = PostAudit.count
      sql = PostAudit.batch_insert_sql(force: true) do
        Post.create!(title: "SQL only audit block 1")
        Post.create!(title: "SQL only audit block 2")
      end

      expect(sql).to include("INSERT")
      expect(PostAudit.count).to eq(before_count)
    end
  end
end
