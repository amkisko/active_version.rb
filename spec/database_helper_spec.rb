require "spec_helper"

RSpec.describe DatabaseHelper do
  describe ".postgresql_connection_config" do
    around do |example|
      previous = ENV.to_h
      example.run
    ensure
      ENV.replace(previous)
    end

    it "uses DATABASE_URL as polyrun set it, including a shard name" do
      ENV["DATABASE_URL"] = "postgres://postgres@localhost:5432/active_version_test_2"
      ENV["POLYRUN_SHARD_TOTAL"] = "5"
      ENV["POLYRUN_SHARD_INDEX"] = "2"

      expect(described_class.postgresql_connection_config).to eq(
        "postgres://postgres@localhost:5432/active_version_test_2"
      )
    end

    it "uses TEST_DB_NAME from polyrun when DATABASE_URL is absent" do
      ENV.delete("DATABASE_URL")
      ENV.delete("PGDATABASE")
      ENV["TEST_DB_NAME"] = "active_version_test_2"

      expect(described_class.postgresql_connection_config).to include(database: "active_version_test_2")
    end

    it "keeps the base database name for a serial run" do
      ENV.delete("DATABASE_URL")
      ENV.delete("PGDATABASE")
      ENV.delete("TEST_DB_NAME")
      ENV.delete("POLYRUN_SHARD_TOTAL")
      ENV.delete("POLYRUN_SHARD_INDEX")

      expect(described_class.postgresql_connection_config).to include(database: "active_version_test")
    end
  end

  describe ".setup" do
    around do |example|
      previous = ENV.to_h
      example.run
    ensure
      ENV.replace(previous)
    end

    it "keeps the posts relation when schema already exists", :aggregate_failures do
      described_class.setup
      skip "PostgreSQL relation identity" unless postgres_adapter?

      relation_id = posts_relation_id
      described_class.setup
      expect(posts_relation_id).to eq(relation_id)
      expect { Post.create!(title: "after-second-setup") }.not_to raise_error
    end

    it "stops when the connected database is not TEST_DB_NAME" do
      skip "PostgreSQL current_database" unless postgres_available?

      ENV["DATABASE_URL"] = "postgres://postgres@localhost:5432/active_version_test"
      ENV["TEST_DB_NAME"] = "active_version_test_2"

      expect { described_class.setup }.to raise_error(RuntimeError, /TEST_DB_NAME/)
    end
  end

  def postgres_adapter?
    ActiveRecord::Base.connection.adapter_name.match?(/postgres/i)
  end

  def postgres_available?
    described_class.establish_test_connection
    postgres_adapter?
  rescue
    false
  end

  def posts_relation_id
    ActiveRecord::Base.connection.select_value(
      "SELECT oid FROM pg_class WHERE relname = 'posts' AND relkind = 'r'"
    )
  end
end
