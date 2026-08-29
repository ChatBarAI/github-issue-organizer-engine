module GithubIssueOrganizerEngine
  class GithubIdentity < ApplicationRecord
    belongs_to :user,
      class_name: GithubIssueOrganizerEngine.configuration.user_class_name,
      inverse_of: false

    before_validation :normalize_login

    validates :user_id, uniqueness: true
    validates :github_user_id, presence: true, uniqueness: true
    validates :github_login,
      presence: true,
      uniqueness: { case_sensitive: false },
      format: {
        with: /\A[a-z\d](?:[a-z\d-]{0,37}[a-z\d])?\z/i,
        message: "is not a valid GitHub username"
      }

    private

    def normalize_login
      self.github_login = github_login.to_s.delete_prefix("@").strip
    end
  end
end
