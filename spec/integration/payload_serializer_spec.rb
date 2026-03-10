require "spec_helper"
require "support/database"
require "support/models"
require "support/integration_helpers"

RSpec.describe "ActiveVersion payload serializer integration", type: :integration do
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

  describe "YAML serialization for text columns" do
    it "serializes complex data structures to YAML for text columns" do
      # Create audit with complex changes
      post = Post.create!(title: "Hello", body: "World")
      expect(post.audits.count).to eq(1)
      expect(post.audits.first.action).to eq("create")

      # Reload to ensure clean state
      post.reload

      # Update with nested changes - use update! to ensure callbacks are triggered
      post.update!(title: "Updated", body: "New body")

      # Reload to get fresh audit count
      post.reload
      expect(post.audits.count).to eq(2)
      # Get the update audit (version 2)
      audit = post.audits.order(version: :asc).last
      expect(audit.action).to eq("update")

      # Verify changes are stored and can be retrieved
      expect(audit.audited_changes).to be_a(Hash)
      expect(audit.audited_changes).to have_key("title")
      # Changes should be in ["old", "new"] format for updates
      expect(audit.audited_changes["title"]).to be_an(Array)
      expect(audit.audited_changes["title"][0]).to eq("Hello")
      expect(audit.audited_changes["title"][1]).to eq("Updated")
    end

    it "handles YAML serialization and deserialization correctly" do
      post = Post.create!(title: "Test")

      # Create complex context data
      complex_context = {
        "nested" => {
          "key" => "value",
          "array" => [1, 2, 3],
          "boolean" => true
        },
        "timestamp" => Time.current.iso8601
      }

      ActiveVersion.with_context(complex_context) do
        post.title = "Updated"
        post.save!
      end

      post.reload
      audit = post.audits.order(version: :asc).last
      expect(audit.action).to eq("update")

      # Reload to ensure we get fresh data from database
      audit.reload
      context = audit.audited_context

      # Verify complex data structure is preserved
      expect(context).to be_a(Hash)
      expect(context).not_to be_empty
      expect(context["nested"]).to be_a(Hash)
      expect(context["nested"]["key"]).to eq("value")
      expect(context["nested"]["array"]).to eq([1, 2, 3])
      expect(context["nested"]["boolean"]).to be(true)
    end

    it "preserves data types through serialization" do
      post = Post.create!(title: "Test")

      # Create context with various data types
      typed_context = {
        "string" => "text",
        "integer" => 42,
        "float" => 3.14,
        "boolean_true" => true,
        "boolean_false" => false,
        "nil_value" => nil,
        "array" => [1, "two", 3.0],
        "hash" => {"nested" => "value"}
      }

      ActiveVersion.with_context(typed_context) do
        post.title = "Updated"
        post.save!
      end

      post.reload
      audit = post.audits.order(version: :asc).last
      expect(audit.action).to eq("update")

      # Reload to ensure we get fresh data from database
      audit.reload
      context = audit.audited_context

      # Verify all types are preserved
      expect(context).to be_a(Hash)
      expect(context).not_to be_empty
      expect(context["string"]).to eq("text")
      expect(context["integer"]).to eq(42)
      expect(context["float"]).to eq(3.14)
      expect(context["boolean_true"]).to be(true)
      expect(context["boolean_false"]).to be(false)
      expect(context["nil_value"]).to be_nil
      expect(context["array"]).to eq([1, "two", 3.0])
      expect(context["hash"]).to eq({"nested" => "value"})
    end

    it "handles large data structures" do
      post = Post.create!(title: "Test")

      # Create large context
      large_context = {}
      100.times { |i| large_context["key_#{i}"] = "value_#{i}" }

      ActiveVersion.with_context(large_context) do
        post.title = "Updated"
        post.save!
      end

      post.reload
      audit = post.audits.order(version: :asc).last
      expect(audit.action).to eq("update")

      # Reload to ensure we get fresh data from database
      audit.reload
      context = audit.audited_context

      expect(context).to be_a(Hash)
      expect(context.keys.length).to eq(100)
      expect(context["key_50"]).to eq("value_50")
    end

    it "handles special characters in serialized data" do
      post = Post.create!(title: "Test")

      special_context = {
        "newline" => "line1\nline2",
        "quote" => 'text with "quotes"',
        "unicode" => "café 🎉",
        "special_chars" => "!@#$%^&*()"
      }

      ActiveVersion.with_context(special_context) do
        post.title = "Updated"
        post.save!
      end

      post.reload
      audit = post.audits.order(version: :asc).last
      expect(audit.action).to eq("update")

      # Reload to ensure we get fresh data from database
      audit.reload
      context = audit.audited_context

      expect(context).to be_a(Hash)
      expect(context).not_to be_empty
      expect(context["newline"]).to eq("line1\nline2")
      expect(context["quote"]).to eq('text with "quotes"')
      expect(context["unicode"]).to eq("café 🎉")
      expect(context["special_chars"]).to eq("!@#$%^&*()")
    end

    it "round-trips data through database correctly" do
      post = Post.create!(title: "Original")

      original_context = {
        "test" => "data",
        "number" => 123,
        "nested" => {"inner" => "value"}
      }

      ActiveVersion.with_context(original_context) do
        post.title = "Changed"
        post.save!
      end

      # Reload from database using correct column names
      audit = PostAudit.find_by(auditable_id: post.id, auditable_type: "Post", version: 2)
      expect(audit).to be_present

      # Reload to ensure we get fresh data from database
      audit.reload
      context = audit.audited_context
      expect(context).to be_a(Hash)
      expect(context).not_to be_empty
      expect(context["test"]).to eq("data")
      expect(context["number"]).to eq(123)
      expect(context["nested"]["inner"]).to eq("value")
    end

    it "uses JSON serializer for json_column storage" do
      serializer = PostAudit.serializer_for_column("audited_changes")
      data = {"key" => "value", "number" => 42}
      dumped = serializer.dump(data)
      loaded = serializer.load(dumped)

      expect(serializer).to be_a(ActiveVersion::Audits::AuditRecord::Serializers::Json)
      expect(dumped).to be_a(String)
      expect(loaded).to eq(data)
    end
  end
end
