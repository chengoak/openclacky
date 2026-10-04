# frozen_string_literal: true
require "spec_helper"
require "clacky/server/http_server"

RSpec.describe Clacky::Server::HttpServer, "web-originated turn progress card (#603)" do
  def build_server(registry, channel_manager)
    config = Clacky::AgentConfig.new
    agent = double("agent", history: [], name: "Session 1")
    web_ui = double("web_ui")
    server = described_class.allocate.tap do |s|
      s.instance_variable_set(:@registry, registry)
      s.instance_variable_set(:@agent_config, config)
      s.instance_variable_set(:@ws_mutex, Mutex.new)
      s.instance_variable_set(:@ws_clients, {})
      s.instance_variable_set(:@all_ws_conns, [])
      s.instance_variable_set(:@channel_manager, channel_manager)
    end

    registry.create(session_id: "s")
    registry.with_session("s") { |s| s[:agent] = agent; s[:ui] = web_ui; s[:status] = :idle }
    allow(agent).to receive_messages(parse_skill_command: { found: false }, rename: nil)
    allow(web_ui).to receive(:show_user_message)
    allow(server).to receive(:broadcast)
    [server, agent]
  end

  it "starts a channel progress card once the web task actually runs" do
    config = Clacky::AgentConfig.new
    registry = Clacky::Server::SessionRegistry.new(agent_config: config)
    channel_ui = double("channel_ui")
    channel_manager = double("channel_manager", channel_ui_for_session: channel_ui)
    server, agent = build_server(registry, channel_manager)

    expect(channel_ui).to receive(:start_task).with(reply_to: nil)
    allow(server).to receive(:run_agent_task) { |&task| task.call; true }
    expect(agent).to receive(:run)
    server.send(:handle_user_message, "s", "hello")
  end

  it "does not start a card when the concurrency cap rejects the web task" do
    config = Clacky::AgentConfig.new
    registry = Clacky::Server::SessionRegistry.new(agent_config: config)
    channel_ui = double("channel_ui")
    channel_manager = double("channel_manager", channel_ui_for_session: channel_ui)
    server, agent = build_server(registry, channel_manager)

    # run_agent_task returns early on running_full? without invoking the block.
    allow(server).to receive(:run_agent_task)
    expect(channel_ui).not_to receive(:start_task)
    expect(agent).not_to receive(:run)
    server.send(:handle_user_message, "s", "hello")
  end
end
