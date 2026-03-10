require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Adapters::ActiveRecord::Base do
  before(:all) do
    DatabaseHelper.setup
  end

  after(:all) do
    DatabaseHelper.teardown
  end

  it "exposes column_names on instances via class delegation" do
    expect(Post.new.column_names).to eq(Post.column_names)
  end

  it "reports versioning registration through has_versioning?" do
    expect(Post.has_versioning?(:audits)).to eq(true)
    expect(Post.has_versioning?(:revisions)).to eq(true)
    expect(Post.has_versioning?(:translations)).to eq(true)
  end

  it "returns version classes through version_class_for" do
    expect(Post.version_class_for(:audits)).to eq(PostAudit)
    expect(Post.version_class_for(:unknown)).to be_nil
  end
end
