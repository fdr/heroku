require "spec_helper"
require "heroku/command/logs"

module Heroku::Command
  describe Logs do
    before do
      @cli = prepare_command(Logs)
    end

    it "shows the app logs" do
      @cli.heroku.should_receive(:read_logs).with('myapp', [])
      @cli.index
    end

    it "shows the app cron logs" do
      @cli.heroku.should_receive(:cron_logs).with('myapp').and_return('cron logs')
      @cli.should_receive(:display).with('cron logs')
      @cli.cron
    end
  end
end
