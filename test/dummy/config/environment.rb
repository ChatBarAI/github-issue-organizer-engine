require_relative "application"

GithubIssueOrganizerEngine.configure do |config|
  config.authorize_with = lambda do
    @host_session_path = main_app.destroy_user_session_path
  end
  config.current_user_id = -> { nil }
  config.layout = "application"
end

Dummy::Application.initialize!
