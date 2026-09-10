module GithubIssueOrganizerEngine
  class TimelineRescheduler
    def initialize(timeline:, starts_on: timeline.starts_on, allow_reassignment: true, ordered_item_ids: nil)
      @timeline = timeline
      @starts_on = Date.parse(starts_on.to_s)
      @allow_reassignment = allow_reassignment
      @ordered_item_ids = ordered_item_ids
    end

    def call
      result = Scheduler.new(
        issues: scheduler_issues,
        starts_on: @starts_on,
        developer_ids: @timeline.developer_ids,
        ordered_issue_ids: @ordered_item_ids,
        strict_issue_order: @ordered_item_ids.present?,
        unavailability: @timeline.unavailabilities.reject(&:destroyed?).map do |period|
          {
            developer_id: period.developer_id,
            starts_at: period.starts_at,
            ends_at: period.ends_at
          }
        end
      ).call

      @timeline.transaction do
        @timeline.update!(starts_on: @starts_on)
        offset = @timeline.items.size
        @timeline.items.update_all("position = position + #{Integer(offset)}")
        @timeline.items.each(&:reload)
        result.scheduled.each do |scheduled|
          item = items_by_key.fetch([ scheduled["repository"], scheduled["issue_number"] ])
          item.update!(
            starts_on: scheduled["starts_on"],
            ends_on: scheduled["ends_on"],
            work_segments: scheduled["work_segments"],
            developer_id: scheduled["developer_id"],
            developer_position: scheduled["developer_position"],
            position: scheduled["position"]
          )
        end
      end

      @timeline
    end

    private

    def items_by_key
      @items_by_key ||= @timeline.items.index_by { |item| [ item.repository, item.issue_number ] }
    end

    def scheduler_issues
      @timeline.items.map do |item|
        effort_label = Scheduler::EFFORT_HOURS.key(item.effort_hours)
        raise ArgumentError, "Issue ##{item.issue_number} has an unsupported effort" unless effort_label

        issue = {
          "id" => item.id,
          "github_issue_id" => item.github_issue_id,
          "number" => item.issue_number,
          "title" => item.title,
          "html_url" => item.url,
          "repository_url" => "https://api.github.com/repos/#{item.repository}",
          "created_at" => Time.at(item.position).utc.iso8601,
          "labels" => [ item.priority, effort_label ].map { |name| { "name" => name } },
          "assignees" => [
            {
              "id" => item.github_assignee_id,
              "login" => item.github_assignee_login
            }.compact
          ].reject(&:empty?)
        }
        if item.starts_on < @starts_on
          issue["carried_starts_on"] = item.starts_on.iso8601
          issue["carried_work_segments"] = Array(item.work_segments)
          issue["carried_developer_id"] = item.developer_id
        end
        issue["assigned_developer_id"] = item.developer_id unless @allow_reassignment
        issue
      end
    end
  end
end
