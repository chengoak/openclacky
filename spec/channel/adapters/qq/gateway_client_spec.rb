# frozen_string_literal: true

require "clacky/server/channel/adapters/qq/gateway_client"

RSpec.describe Clacky::Channel::Adapters::Qq::GatewayClient do
  let(:client) do
    described_class.new(
      url: "wss://example.com/gateway",
      token: "access-token",
      intents: 1 << 25
    )
  end

  describe "#backoff_seconds" do
    it "grows exponentially, staying within +/-50% jitter bounds" do
      delays = Array.new(4) { client.send(:backoff_seconds) }
      expect(delays[0]).to be_between(1, 3)
      expect(delays[1]).to be_between(2, 6)
      expect(delays[2]).to be_between(4, 12)
      expect(delays[3]).to be_between(8, 24)
    end

    it "never exceeds MAX_BACKOFF_S even after many attempts" do
      delays = Array.new(12) { client.send(:backoff_seconds) }
      expect(delays.last).to be <= described_class::MAX_BACKOFF_S
    end
  end

  describe "#reset_backoff" do
    it "restarts the attempt counter" do
      3.times { client.send(:backoff_seconds) }
      client.send(:reset_backoff)
      delay = client.send(:backoff_seconds)
      expect(delay).to be <= described_class::BASE_BACKOFF_S * 1.5
    end
  end
end
