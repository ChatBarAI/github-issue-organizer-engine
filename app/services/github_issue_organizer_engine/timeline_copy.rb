module GithubIssueOrganizerEngine
  class TimelineCopy
    TIMELINE_ATTRIBUTES = %w[
      starts_on query developer_count developer_ids in_review_issues blocked_issues needs_effort_issues
    ].freeze
    CHILD_IGNORED_ATTRIBUTES = %w[id timeline_id created_at updated_at].freeze

    def initialize(timeline:, editor_id:, timeline_class: Timeline)
      @timeline = timeline
      @editor_id = editor_id
      @timeline_class = timeline_class
    end

    def call
      raise ArgumentError, "No host user is available" if @editor_id.blank?

      @timeline_class.transaction do
        copy = @timeline_class.create!(
          @timeline.attributes.slice(*TIMELINE_ATTRIBUTES).merge(
            "created_by_id" => @timeline.created_by_id,
            "edited_by_id" => @editor_id,
            "source_timeline_id" => @timeline.id,
            "status" => @timeline_class.statuses.fetch(:draft)
          )
        )

        @timeline.items.each do |item|
          copy.items.create!(item.attributes.except(*CHILD_IGNORED_ATTRIBUTES))
        end
        @timeline.unavailabilities.each do |period|
          copy.unavailabilities.create!(period.attributes.except(*CHILD_IGNORED_ATTRIBUTES))
        end

        copy
      end
    end
  end
end
