module GithubIssueOrganizerEngine
  class Timeline < ApplicationRecord
    enum :status,
      { draft: "draft", current: "current", obsolete: "obsolete" },
      default: :draft,
      validate: true

    belongs_to :created_by,
      class_name: GithubIssueOrganizerEngine.configuration.user_class_name,
      inverse_of: false

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

    def make_current!
      raise ArgumentError, "Only a draft timeline can be made current" unless draft?

      self.class.transaction do
        self.class.lock.where(status: :current).where.not(id: id).update_all(
          status: self.class.statuses.fetch(:obsolete),
          updated_at: Time.current
        )
        update!(status: :current)
      end
    end

    private

    def developer_ids_are_present
      errors.add(:developer_ids, "must include at least one developer ID") if developer_ids.empty?
    end
  end
end
