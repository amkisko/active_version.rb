require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Audits::HasAudits do
  before do
    DatabaseHelper.setup
    stub_const("SpecialPost", Class.new(Post))
  end

  it "keeps subclass audits visible through the polymorphic association" do
    record = SpecialPost.create!(title: "inherited")
    record.update!(title: "updated")

    aggregate_failures do
      expect(record.audits.count).to eq(2)
      expect(record.audits.order(:version).pluck(:auditable_type)).to eq(["Post", "Post"])
    end
  end
end
