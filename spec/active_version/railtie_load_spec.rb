require "spec_helper"

RSpec.describe "ActiveVersion Railtie load guard" do
  it "does not require railtie when only an empty Rails module exists" do
    lib = File.expand_path("../../lib", __dir__)
    script = "module Rails; end; require 'active_version'; print defined?(ActiveVersion::Railtie).inspect"
    output = `bundle exec ruby -I#{lib} -e #{script.inspect}`
    expect($?.success?).to be true
    expect(output).to eq("nil")
  end

  it "defines ActiveVersion::Railtie when Rails is fully loaded in this process" do
    skip "Rails::Railtie not loaded" unless defined?(Rails::Railtie)
    expect(defined?(ActiveVersion::Railtie)).to eq("constant")
  end
end
