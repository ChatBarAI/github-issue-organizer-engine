Rails.application.routes.draw do
  get "/admin", to: ->(_env) { [ 200, {}, [ "Admin" ] ] }, as: :admin_root
  delete "/users/sign_out", to: ->(_env) { [ 204, {}, [] ] }, as: :destroy_user_session

  mount GithubIssueOrganizerEngine::Engine => "/admin/github-issues",
    as: :github_issue_organizer_engine
end
