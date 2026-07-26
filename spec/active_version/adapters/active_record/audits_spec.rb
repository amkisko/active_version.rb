require "spec_helper"
require "support/database"
require "support/models"

RSpec.describe ActiveVersion::Adapters::ActiveRecord::Audits do
  it "loads fallback on_load hook when adapter is not yet included" do
    adapter_file = File.expand_path(
      "../../../../lib/active_version/adapters/active_record/audits.rb",
      __dir__
    )

    executed_on_load_block = false
    on_load_calls = 0
    allow(ActiveRecord::Base).to receive(:include?).and_return(false)
    allow(ActiveSupport).to receive(:on_load).with(:active_record) do |_name, &blk|
      on_load_calls += 1
      if blk
        executed_on_load_block = true
        ActiveRecord::Base.class_eval(&blk)
      end
    end

    load adapter_file

    expect(executed_on_load_block).to be(true)
    expect(on_load_calls).to be >= 2
  end
end
