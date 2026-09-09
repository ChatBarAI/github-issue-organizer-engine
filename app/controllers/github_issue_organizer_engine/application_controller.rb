module GithubIssueOrganizerEngine
  class ApplicationController < ::ApplicationController
    before_action :authorize_host_user!

    layout -> { "github_issue_organizer_engine/application" if GithubIssueOrganizerEngine.configuration.layout }

    private

    def authorize_host_user!
      callback = GithubIssueOrganizerEngine.configuration.authorize_with
      return instance_exec(&callback) if callback

      head :forbidden
    end

    def current_host_user_id
      callback = GithubIssueOrganizerEngine.configuration.current_user_id
      instance_exec(&callback)
    end

    def current_github_identity
      return if current_host_user_id.blank?

      GithubIssueOrganizerEngine::GithubIdentity.find_by(user_id: current_host_user_id)
    end

    def github_client
      token_callback = GithubIssueOrganizerEngine.configuration.github_token
      token = instance_exec(&token_callback)
      GithubIssueOrganizerEngine::Github::Client.new(
        token: token,
        repositories: configured_repositories
      )
    end

    def configured_repositories
      return GithubIssueOrganizerEngine.configuration.repositories unless defined?(::ActiveRecord::Base)
      return GithubIssueOrganizerEngine.configuration.repositories unless Setting.table_exists?

      Setting.current.repositories
    rescue ::ActiveRecord::ConnectionNotEstablished
      GithubIssueOrganizerEngine.configuration.repositories
    end

    def configured_developer_ids
      return [] unless defined?(::ActiveRecord::Base)
      return [] unless Setting.table_exists?

      Setting.current.developer_ids
    rescue ::ActiveRecord::ConnectionNotEstablished
      []
    end
  end
end
