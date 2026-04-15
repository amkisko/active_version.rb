require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe "Stack coverage (audit / revision / SQL builders)" do
  before(:all) do
    DatabaseHelper.setup
  end

  before do
    Post.destroy_all
    PostAudit.destroy_all
    PostRevision.destroy_all
    ActiveVersion.clear_context!
    ActiveVersion.auditing_enabled = true
  end

  describe "Audits::SQLBuilder" do
    it "supports BatchCollector#add, #concat, and #to_a" do
      p1 = Post.create!(title: "A")
      p2 = Post.create!(title: "B")
      p1.update!(title: "A1")
      p2.update!(title: "B1")

      seen = []
      PostAudit.batch_insert_sql(force: true) do |batch|
        batch.add(p1)
        batch.concat([p2])
        seen = batch.to_a
      end

      expect(seen.map(&:id).sort).to eq([p1.id, p2.id].sort)
    end

    it "returns multiple statements when combine is false for arity-0 batch capture" do
      sql = PostAudit.batch_insert_sql(force: true, combine: false) do
        Post.create!(title: "cap1")
        Post.create!(title: "cap2")
      end

      expect(sql).to include(";\n")
      expect(sql.scan(/INSERT/i).size).to eq(2)
    end

    it "accepts options-only first argument via normalize_batch_arguments" do
      sql = PostAudit.batch_insert_sql({force: true, combine: false}) do
        p = Post.create!(title: "norm")
        p.update!(title: "norm2")
      end
      expect(sql).to be_a(String)
      expect(sql).to include("INSERT")
    end

    it "includes allow_saved path in build_batch_audit_values" do
      p = Post.create!(title: "saved")
      sql = PostAudit.batch_insert_sql([p], allow_saved: true, combine: false)
      expect(sql).to include("INSERT")
    end

    it "sets polymorphic user type when RequestStore has audited_user" do
      post = Post.create!(title: "u1")
      post.update!(title: "u2")
      user = double("User", id: 42, class: double("UserClass", name: "User"))
      ActiveVersion::RequestStore.audited_user = user

      sql = PostAudit.batch_insert_sql([post], force: true)
      expect(sql).to include("INSERT")
      expect(sql).to include("42")
      expect(sql).to include("User")
    ensure
      ActiveVersion::RequestStore.audited_user = nil
    end

    it "uses active_version_auditable_id_value when identity map is absent" do
      post = Post.create!(title: "idmap")
      post.update!(title: "idmap2")
      allow(post).to receive(:respond_to?).and_wrap_original do |method, name, *args|
        case name.to_sym
        when :active_version_audit_identity_map
          false
        when :active_version_auditable_id_value
          true
        else
          method.call(name, *args)
        end
      end
      allow(post).to receive(:active_version_auditable_id_value).and_return(post.id)

      sql = PostAudit.batch_insert_sql([post], force: true)
      expect(sql).to include("INSERT")
    end

    it "passes scalar values through prepare_sql_value" do
      post = Post.create!(title: "prep")
      post.update!(title: "prep2")
      allow(post).to receive(:audited_changes).and_return({"title" => BigDecimal("1.5")})
      sql = PostAudit.batch_insert_sql([post], force: true)
      expect(sql).to include("INSERT")
    end
  end

  describe "Revisions::SQLBuilder" do
    it "supports BatchCollector#add, #concat, and #to_a" do
      p1 = Post.create!(title: "rA")
      p2 = Post.create!(title: "rB")
      p1.update!(title: "rA1")
      p2.update!(title: "rB1")

      PostRevision.batch_insert_sql(version: 1, force: true) do |batch|
        batch.add(p1)
        batch.concat([p2])
        expect(batch.to_a.length).to eq(2)
      end
    end

    it "returns multiple INSERTs when combine is false and block capture fills values" do
      sql = PostRevision.batch_insert_sql(version: 1, force: true, combine: false) do
        p1 = Post.create!(title: "b1")
        p2 = Post.create!(title: "b2")
        p1.update!(title: "b1x")
        p2.update!(title: "b2x")
      end

      expect(sql).to include(";\n")
      expect(sql.scan(/INSERT/i).size).to eq(2)
    end

    it "invokes arity-0 block branch in batch_insert_sql" do
      sql = PostRevision.batch_insert_sql(version: 1, force: true) do
        p = Post.create!(title: "zero")
        p.update!(title: "zerox")
      end
      expect(sql).to include("INSERT")
    end

    it "uses resolve_batch_records arity-0 yield path" do
      p = Post.create!(title: "y0")
      p.update!(title: "y0x")
      sql = PostRevision.batch_insert_sql(version: 1, force: true) { nil }
      expect(sql).to eq("")
    end

    it "uses resolve_batch_records arity-1 batch collector with explicit records" do
      p = Post.create!(title: "arity1")
      p.update!(title: "arity1x")
      sql = PostRevision.batch_insert_sql([p], version: 1, force: true) do |batch|
        batch.add(p)
      end
      expect(sql).to include("INSERT")
    end

    it "builds ON CONFLICT DO NOTHING when upsert has only conflict columns" do
      sql = PostRevision.send(
        :build_combined_insert_sql,
        PostRevision,
        [{"post_id" => 1, "version" => 1}],
        upsert: true,
        conflict_target: [:post_id, :version]
      )
      expect(sql).to include("DO NOTHING")
    end

    it "normalizes Date values in prepare_sql_value" do
      d = Date.new(2024, 6, 1)
      v = PostRevision.send(:prepare_sql_value, d)
      expect(v).to be_a(Time)
      expect(v.utc_offset).to eq(0)
    end
  end

  describe "RevisionManipulation refreshable columns" do
    it "reads refresh values via [] when the row does not respond to the column method" do
      post = Post.create!(title: "rf1")
      post.update!(title: "rf2")

      fake_row = Object.new
      def fake_row.respond_to?(name, *)
        name.to_s == "[]" || name.to_s == "[]="
      end
      def fake_row.[](key)
        {"title" => "from_bracket", "updated_at" => Time.current}[key.to_s]
      end

      allow(post).to receive(:refreshable_column_names).and_return(["title"])
      rel = double("relation")
      allow(rel).to receive(:find).with(post.id).and_return(fake_row)
      allow(post.class).to receive(:select).with(["title"]).and_return(rel)

      expect { post.send(:create_snapshot!) }.not_to raise_error
    end
  end

  describe "RevisionManipulation diff_from" do
    it "resolves from_version by time when version is omitted" do
      post = Post.create!(title: "t0")
      post.update!(title: "t1")
      travel_time = PostRevision.where(post_id: post.id).maximum(:created_at) || Time.current

      diff = post.diff_from(time: travel_time)
      expect(diff).to be_a(Hash)
      expect(diff).to have_key("changes")
    end
  end

  describe "PostAudit save (AuditRecord overrides)" do
    it "uses keyword branch on new records" do
      post = Post.create!(title: "save_kw")
      next_v = PostAudit.where(auditable_type: "Post", auditable_id: post.id).maximum(:version).to_i + 1
      audit = PostAudit.new(
        auditable_type: "Post",
        auditable_id: post.id,
        action: "create",
        version: next_v,
        audited_changes: "{}"
      )
      expect(audit.save(validate: false)).to be(true)
    end

    it "converts a lone positional Hash into keyword args" do
      post = Post.create!(title: "save_hash")
      next_v = PostAudit.where(auditable_type: "Post", auditable_id: post.id).maximum(:version).to_i + 1
      audit = PostAudit.new(
        auditable_type: "Post",
        auditable_id: post.id,
        action: "create",
        version: next_v,
        audited_changes: "{}"
      )
      expect(audit.save({validate: false})).to be(true)
    end
  end
end
