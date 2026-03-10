require "spec_helper"

RSpec.describe "ActiveVersion Time Parsing" do
  describe "ActiveVersion.parse_time" do
    it "parses Numeric (Unix timestamp)" do
      time = Time.zone.at(1609459200) # 2021-01-01 00:00:00 UTC
      parsed = ActiveVersion.parse_time(1609459200)
      expect(parsed).to be_within(1.second).of(time)
    end

    it "parses String" do
      time_string = "2021-01-01 12:00:00"
      parsed = ActiveVersion.parse_time(time_string)
      expect(parsed).to be_a(Time)
    end

    it "parses Date" do
      date = Date.new(2021, 1, 1)
      parsed = ActiveVersion.parse_time(date)
      expect(parsed).to be_a(Time)
    end

    it "parses Time" do
      time = Time.current
      parsed = ActiveVersion.parse_time(time)
      expect(parsed).to eq(time)
    end

    it "handles other objects via to_s" do
      obj = double(to_s: "2021-01-01 12:00:00")
      parsed = ActiveVersion.parse_time(obj)
      expect(parsed).to be_a(Time)
    end

    it "falls back to Time when Time.zone is unavailable" do
      allow(Time).to receive(:zone).and_return(nil)
      parsed = ActiveVersion.parse_time("2021-01-01 12:00:00 UTC")
      expect(parsed).to be_a(Time)
    end
  end

  describe "ActiveVersion.parse_time_to_time" do
    it "is an alias for parse_time" do
      time = Time.current
      expect(ActiveVersion.parse_time_to_time(time)).to eq(ActiveVersion.parse_time(time))
    end

    it "returns Time object" do
      parsed = ActiveVersion.parse_time_to_time(Time.current)
      expect(parsed).to be_a(Time)
    end
  end
end
