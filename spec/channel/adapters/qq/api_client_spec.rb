# frozen_string_literal: true

require "clacky/server/channel/adapters/qq/api_client"

RSpec.describe Clacky::Channel::Adapters::Qq::ApiClient do
  let(:client) do
    described_class.new(app_id: "app-1", app_secret: "secret-1")
  end

  describe "#initialize" do
    it "uses the production base url by default" do
      expect(client.base_url).to eq(described_class::DEFAULT_BASE_URL)
    end

    it "accepts an explicit base url" do
      custom = described_class.new(
        app_id: "app-1", app_secret: "secret-1",
        base_url: "https://example.test"
      )
      expect(custom.base_url).to eq("https://example.test")
    end
  end

  describe "ApiError" do
    it "carries an optional code and http status" do
      err = described_class::ApiError.new("bad", code: 100, http_status: 400)
      expect(err.message).to eq("bad")
      expect(err.code).to eq(100)
      expect(err.http_status).to eq(400)
    end
  end
end
