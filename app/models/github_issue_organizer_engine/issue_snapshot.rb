module GithubIssueOrganizerEngine
  class IssueSnapshot < ApplicationRecord
    belongs_to :timeline, optional: true

    validates :captured_at, presence: true

    def total
      priority_counts.values.sum
    end
  end
end
