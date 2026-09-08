module GithubIssueOrganizerEngine
  class Timeline < ApplicationRecord
    enum :status,
      { draft: "draft", current: "current", obsolete: "obsolete" },
      default: :draft,
      validate: true

    belongs_to :created_by,
      class_name: GithubIssueOrganizerEngine.configuration.user_class_name,
      inverse_of: false

    belongs_to :edited_by,
      class_name: GithubIssueOrganizerEngine.configuration.user_class_name,
      optional: true,
      inverse_of: false

    belongs_to :source_timeline,
      class_name: "GithubIssueOrganizerEngine::Timeline",
      optional: true,
      inverse_of: :derived_timelines

    has_many :derived_timelines,
      class_name: "GithubIssueOrganizerEngine::Timeline",
      foreign_key: :source_timeline_id,
      dependent: :nullify,
      inverse_of: :source_timeline

    has_many :items,
      -> { order(:position) },
      class_name: "GithubIssueOrganizerEngine::TimelineItem",
      dependent: :destroy,
      inverse_of: :timeline

    has_many :unavailabilities,
      -> { order(:starts_at) },
      class_name: "GithubIssueOrganizerEngine::TimelineUnavailability",
      dependent: :destroy,
      inverse_of: :timeline

    validates :starts_on, presence: true
    validates :developer_count,
      numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
    validate :developer_ids_are_present

    def ends_on
      items.map(&:ends_on).compact.max
    end

    def original_created_at
      source_timeline&.original_created_at || created_at
    end

    def make_current!(github_client:, repositories:)
      raise ArgumentError, "Only a draft timeline can be made current" unless draft?

      counts = IssuePriorityCounts.call(github_client.open_issues)
      self.class.transaction do
        lock!
        raise ArgumentError, "Only a draft timeline can be made current" unless draft?

        self.class.lock.where(status: :current).where.not(id: id).update_all(
          status: self.class.statuses.fetch(:obsolete),
          updated_at: Time.current
        )
        source_timeline.update!(status: :obsolete) if source_timeline&.draft?
        update!(status: :current)
        IssueSnapshot.create!(timeline: self, captured_at: Time.current,
          repositories: repositories, priority_counts: counts)
      end
    end

    private

    def developer_ids_are_present
      errors.add(:developer_ids, "must include at least one developer ID") if developer_ids.empty?
    end
  end
end
