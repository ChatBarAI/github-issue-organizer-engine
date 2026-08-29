module GithubIssueOrganizerEngine
  class TimelineItem < ApplicationRecord
    belongs_to :timeline,
      class_name: "GithubIssueOrganizerEngine::Timeline",
      inverse_of: :items

    validates :repository, :issue_number, :title, :url, :developer_id,
      :priority, :effort_hours, :starts_on, :ends_on, :position,
      presence: true

    validates :developer_position, numericality: { only_integer: true, greater_than: 0 }

    def github_assignee_matches_developer?
      [ github_assignee_id, github_assignee_login ].compact.any? do |identifier|
        developer_id.casecmp?(identifier)
      end
    end
  end
end
