module GithubIssueOrganizerEngine
  class TimelineGapFiller
    def initialize(timeline:, from_date:)
      @timeline = timeline
      @from_date = Date.iso8601(from_date.to_s)
    rescue Date::Error
      raise ArgumentError, "Choose a valid date to fill gaps from"
    end

    def call
      @timeline.transaction do
        items = @timeline.items.to_a
        eligible, fixed = items.partition { |item| item.starts_on >= @from_date }
        eligible.sort_by! do |item|
          [item.starts_on, Array(item.work_segments).first&.fetch("starts_at", nil).to_s, item.position]
        end
        unavailable = @timeline.unavailabilities.map do |period|
          { developer_id: period.developer_id, starts_at: period.starts_at, ends_at: period.ends_at }
        end
        # Keep the queue behind work that started before the cutoff, including
        # all remaining segments of an issue spanning the selected date.
        fixed.each do |item|
          finish = Array(item.work_segments).map { |segment| DateTime.iso8601(segment.fetch("ends_at")) }.max ||
            item.ends_on.to_datetime + Rational(17, 24)
          next unless finish > @from_date.to_datetime

          unavailable << { developer_id: item.developer_id, starts_at: @from_date.to_datetime, ends_at: finish }
        end
        result = Scheduler.new(
          issues: eligible.map { |item| scheduler_issue(item) },
          starts_on: @from_date,
          developer_ids: @timeline.developer_ids,
          ordered_issue_ids: eligible.map(&:id),
          strict_issue_order: true,
          unavailability: unavailable
        ).call
        by_key = eligible.index_by { |item| [item.repository, item.issue_number] }
        result.scheduled.each do |scheduled|
          by_key.fetch([scheduled["repository"], scheduled["issue_number"]]).update!(
            starts_on: Date.iso8601(scheduled.fetch("starts_on")),
            ends_on: Date.iso8601(scheduled.fetch("ends_on")),
            work_segments: scheduled.fetch("work_segments")
          )
        end
      end
      @timeline
    end

    private

    def scheduler_issue(item)
      effort = Scheduler::EFFORT_HOURS.key(item.effort_hours)
      raise ArgumentError, "Issue ##{item.issue_number} has an unsupported effort" unless effort

      {
        "id" => item.id,
        "number" => item.issue_number,
        "title" => item.title,
        "html_url" => item.url,
        "repository_url" => "https://api.github.com/repos/#{item.repository}",
        "labels" => [item.priority, effort],
        "assigned_developer_id" => item.developer_id
      }
    end
  end
end
