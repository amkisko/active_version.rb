require "spec_helper"

RSpec.describe ActiveVersion::Audits::AuditRecord::Serializers::Json do
  let(:payload) { {"user_id" => [1, nil]} }

  describe "#dump" do
    it "encodes Hash and Array to a JSON string for text-backed columns" do
      serializer = described_class.new(native: false)

      expect(serializer.dump(payload)).to eq(ActiveVersion.json_encode(payload))
      expect(serializer.dump([1, 2])).to eq(ActiveVersion.json_encode([1, 2]))
    end

    it "keeps Hash and Array native for json and jsonb columns" do
      serializer = described_class.new(native: true)

      expect(serializer.dump(payload)).to eq(payload)
      expect(serializer.dump([1, 2])).to eq([1, 2])
    end

    it "passes through values that are not Hash or Array" do
      serializer = described_class.new(native: false)

      expect(serializer.dump("already")).to eq("already")
      expect(serializer.dump(nil)).to be_nil
    end
  end

  describe "#load" do
    it "parses string-shaped payloads and returns already-native hashes" do
      serializer = described_class.new(native: true)
      encoded = ActiveVersion.json_encode(payload)

      expect(serializer.load(encoded)).to eq(payload)
      expect(serializer.load(payload)).to eq(payload)
      expect(serializer.load(nil)).to eq({})
    end
  end
end
