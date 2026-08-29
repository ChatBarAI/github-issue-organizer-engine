require_relative "github_issue_organizer_engine/version"
require_relative "github_issue_organizer_engine/engine"

module GithubIssueOrganizerEngine
  class Configuration
    attr_accessor :authorize_with,
      :current_user_id,
      :github_token,
      :layout,
      :repositories,
      :user_class_name

    def initialize
      @authorize_with = nil
      @current_user_id = -> { current_user&.id }
      @github_token = -> { nil }
      @layout = "application"
      @user_class_name = "::User"
      @repositories = []
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
