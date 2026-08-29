GithubIssueOrganizerEngine.configure do |config|
  config.layout = "application"
  config.user_class_name = "::User"

  # This block runs in the engine controller context. Keep authorization in
  # the host application so the engine never owns login sessions or roles.
  config.authorize_with = lambda do
    authenticate_user!
    # Add any host-specific authorization check here.
  end

  config.current_user_id = -> { current_user&.id }

  # Keep this credential server-side. Browser JavaScript never receives it.
  config.github_token = lambda do
    Rails.application.credentials.dig(:github, :issue_organizer_token)
  end

  config.repositories = [
    "your-organization/repository-one",
    "your-organization/repository-two"
  ]
end
