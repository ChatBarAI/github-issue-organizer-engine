require "rails"
require "action_controller/railtie"
require "action_view/railtie"

require_relative "../../../lib/github_issue_organizer_engine"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "dummy-host-secret-key-base"
    config.logger = Logger.new(nil)
    config.hosts.clear
  end
end
