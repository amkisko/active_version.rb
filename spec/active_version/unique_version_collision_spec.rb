require "spec_helper"
begin
  require "pg"
rescue LoadError
end

RSpec.describe ActiveVersion::UniqueVersionCollision do
  def collision_record
    klass = Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations

      attr_accessor :version, :email

      def self.name
        "CollisionRecord"
      end

      def self.i18n_scope
        :activerecord
      end
    end
    klass.new
  end

  def exception_with_cause(outer_class, message, cause)
    raise outer_class, message, cause: cause
  rescue outer_class => error
    error
  end

  def record_invalid(attribute, error_code)
    record = collision_record
    record.errors.add(attribute, error_code)
    ActiveRecord::RecordInvalid.new(record)
  end

  it "matches a unique constraint error that names the version column" do
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: duplicate key value violates unique constraint index_post_revisions_on_post_id_and_version"
    )

    expect(described_class.match?(error, version_column: :version)).to eq(true)
  end

  it "does not match a unique constraint error for a different column" do
    error = ActiveRecord::RecordNotUnique.new(
      "PG::UniqueViolation: duplicate key value violates unique constraint index_users_on_email"
    )

    expect(described_class.match?(error, version_column: :version)).to eq(false)
  end

  it "matches RecordInvalid when the version column is taken" do
    expect(described_class.match?(record_invalid(:version, :taken), version_column: :version)).to eq(true)
  end

  it "does not match RecordInvalid when the version column is blank" do
    expect(described_class.match?(record_invalid(:version, :blank), version_column: :version)).to eq(false)
  end

  it "does not match RecordInvalid when another column is taken" do
    expect(described_class.match?(record_invalid(:email, :taken), version_column: :version)).to eq(false)
  end

  it "matches a PG unique violation that names the version column" do
    skip "pg gem required" unless defined?(PG)

    error = exception_with_cause(
      ActiveRecord::StatementInvalid,
      "PG::UniqueViolation: ERROR: duplicate key value violates unique constraint index_post_audits_on_auditable_and_version",
      PG::UniqueViolation.new("ERROR: duplicate key value violates unique constraint index_post_audits_on_auditable_and_version")
    )

    expect(described_class.match?(error, version_column: :version)).to eq(true)
  end

  it "does not match a PG unique violation for another constraint" do
    skip "pg gem required" unless defined?(PG)

    error = exception_with_cause(
      ActiveRecord::StatementInvalid,
      "PG::UniqueViolation: ERROR: duplicate key value violates unique constraint index_users_on_email",
      PG::UniqueViolation.new("ERROR: duplicate key value violates unique constraint index_users_on_email")
    )

    expect(described_class.match?(error, version_column: :version)).to eq(false)
  end

  it "does not match an aborted-transaction statement error" do
    skip "pg gem required" unless defined?(PG)

    error = exception_with_cause(
      ActiveRecord::StatementInvalid,
      "PG::InFailedSqlTransaction: ERROR: current transaction is aborted",
      PG::InFailedSqlTransaction.new("ERROR: current transaction is aborted")
    )

    expect(described_class.match?(error, version_column: :version)).to eq(false)
  end
end
