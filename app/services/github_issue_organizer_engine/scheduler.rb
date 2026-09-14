require "date"
require "time"

module GithubIssueOrganizerEngine
  class Scheduler
    PRIORITY_RANKS = {
      "Priority: Critical" => 0,
      "Priority: High" => 1,
      "Priority: Medium" => 2,
      "Priority: Low" => 3
    }.freeze

    EFFORT_HOURS = {
      "Effort: 4 hrs" => 4,
      "Effort: 1 day" => 8,
      "Effort: 2 days" => 16,
      "Effort: 5 days" => 40,
      "Effort: 30 days" => 240
    }.freeze

    STATUS_LABELS = {
      "Status: Backlog" => "backlog",
      "Status: Blocked" => "blocked",
      "Status: In-progress" => "in_progress",
      "Status: Review" => "in_review"
    }.freeze

    WORKDAY_START_HOUR = 9
    WORKDAY_END_HOUR = 17

    Result = Struct.new(
      :scheduled,
      :in_review,
      :blocked,
      :needs_labels,
      :total_hours,
      :developer_ids,
      keyword_init: true
    ) do
      def developer_count
        developer_ids.size
      end

      def ends_on
        scheduled.filter_map { |item| item["ends_on"] }.max
      end
    end

    def initialize(issues:, starts_on:, developer_ids:, unavailability: [], ordered_issue_ids: [], strict_issue_order: false)
      @issues = issues
      @starts_on = parse_start_date(starts_on)
      @issue_order = Array(ordered_issue_ids).each_with_index.to_h { |id, index| [ id.to_s, index ] }
      @strict_issue_order = strict_issue_order
      @developer_ids = Array(developer_ids).map { |id| id.to_s.strip }.reject(&:empty?).uniq
      unless @developer_ids.size.between?(1, 100)
        raise ArgumentError, "Configure between 1 and 100 developer IDs in Settings"
      end
      @unavailability = normalize_unavailability(unavailability)
    end

    def call
      active, in_review, blocked = classified_issues
      schedulable, needs_labels = active.partition { |issue| scheduling_labels_for(issue).values.all? }
      schedulable.sort_by! do |issue|
        continuation_rank = issue["carried_starts_on"] ? 0 : 1
        if @strict_issue_order
          # Manual ordering applies to remaining work; historical segments stay fixed.
          next [ @issue_order.fetch(issue["id"].to_s, @issue_order.size), parse_time(issue["created_at"]) ]
        end

        labels = scheduling_labels_for(issue)
        [
          continuation_rank,
          PRIORITY_RANKS.fetch(labels[:priority]),
          status_for(issue) == "in_progress" ? 0 : 1,
          @issue_order.fetch(issue["id"].to_s, @issue_order.size),
          parse_time(issue["created_at"])
        ]
      end

      developers = @developer_ids.each_with_index.map do |id, index|
        { id: id, position: index + 1, cursor: workday_start(next_workday(@starts_on)) }
      end
      total_hours = 0

      scheduled = schedulable.each_with_index.map do |issue, index|
        labels = scheduling_labels_for(issue)
        hours = EFFORT_HOURS.fetch(labels[:effort])
        history = historical_segments(issue)
        historical_hours = history.sum { |segment| (DateTime.iso8601(segment.fetch("ends_at")) - DateTime.iso8601(segment.fetch("starts_at"))) * 24 }
        remaining_hours = [hours - historical_hours, 0].max
        preferred_developer_id = preferred_developer_id_for(issue)
        carried_developer_id = @developer_ids.find do |id|
          developer_match?(id, issue["carried_developer_id"])
        end
        assigned_developer_id = (carried_developer_id || issue["assigned_developer_id"]).to_s.strip
        assigned_developer_id = nil if assigned_developer_id.empty?
        eligible_developers = if assigned_developer_id
          developers.select { |candidate| candidate[:id].casecmp?(assigned_developer_id) }
        else
          developers
        end
        raise ArgumentError, "Assigned developer is not part of this timeline" if eligible_developers.empty?

        candidate_schedules = eligible_developers.map do |candidate|
          segments = work_segments(candidate[:cursor], candidate[:id], remaining_hours)
          [ candidate, segments ]
        end
        developer, segments = candidate_schedules.min_by do |candidate, candidate_segments|
          [
            candidate_segments.empty? ? candidate[:cursor] : DateTime.iso8601(candidate_segments.last.fetch("ends_at")),
            developer_match?(candidate[:id], preferred_developer_id) ? 0 : 1,
            candidate[:position]
          ]
        end
        developer[:cursor] = DateTime.iso8601(segments.last.fetch("ends_at")) unless segments.empty?
        segments = history + segments
        starts_on = DateTime.iso8601(segments.first.fetch("starts_at")).to_date
        ends_on = DateTime.iso8601(segments.last.fetch("ends_at")).to_date

        total_hours += hours
        serialize(issue).merge(
          "priority" => labels[:priority],
          "effort" => labels[:effort],
          "effort_hours" => hours,
          "github_assignee_id" => first_github_assignee(issue)&.fetch("id", nil)&.to_s,
          "github_assignee_login" => first_github_assignee(issue)&.fetch("login", nil),
          "github_assignee_matches" => developer_match?(developer[:id], preferred_developer_id),
          "manually_assigned" => issue["manually_assigned"] == true,
          "starts_on" => starts_on.iso8601,
          "ends_on" => ends_on.iso8601,
          "work_segments" => segments,
          "developer_id" => developer[:id],
          "developer_position" => developer[:position],
          "position" => index + 1
        )
      end

      missing = needs_labels.map do |issue|
        labels = scheduling_labels_for(issue)
        serialize(issue).merge(
          "priority" => labels[:priority],
          "effort" => labels[:effort],
          "missing" => [
            ("priority" unless labels[:priority]),
            ("effort" unless labels[:effort])
          ].compact
        )
      end

      Result.new(
        scheduled: scheduled,
        in_review: in_review.map { |issue| serialize_informational(issue) },
        blocked: blocked.map { |issue| serialize_informational(issue) },
        needs_labels: missing,
        total_hours: total_hours,
        developer_ids: @developer_ids
      )
    end

    def tie_groups
      active, = classified_issues
      schedulable = active.select { |issue| scheduling_labels_for(issue).values.all? }

      schedulable
        .group_by { |issue| [ scheduling_labels_for(issue)[:priority], status_for(issue) ] }
        .filter_map do |(priority, status), issues|
          next unless issues.size > @developer_ids.size

          {
            "priority" => priority,
            "status" => status,
            "ranking_key" => "#{priority}:#{status}",
            "issues" => issues.sort_by { |issue| parse_time(issue["created_at"]) }.map do |issue|
              serialize(issue).merge(
                "id" => issue["id"].to_s,
                "created_at" => issue["created_at"],
                "effort" => scheduling_labels_for(issue)[:effort],
                "effort_hours" => EFFORT_HOURS.fetch(scheduling_labels_for(issue)[:effort])
              )
            end
          }
        end
        .sort_by { |group| PRIORITY_RANKS.fetch(group["priority"]) }
    end

    private

    # Only recorded work before the new timeline boundary consumes past effort.
    def historical_segments(issue)
      boundary = @starts_on.to_datetime
      Array(issue["carried_work_segments"]).filter_map do |segment|
        from = DateTime.iso8601(segment.fetch("starts_at"))
        to = [DateTime.iso8601(segment.fetch("ends_at")), boundary].min
        next unless from < to

        { "starts_at" => from.iso8601, "ends_at" => to.iso8601 }
      end.sort_by { |segment| DateTime.iso8601(segment.fetch("starts_at")) }
    end

    def parse_start_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      raise ArgumentError, "Invalid timeline start date"
    end

    def normalize_unavailability(values)
      Array(values).map do |value|
        developer_id = value[:developer_id] || value["developer_id"]
        starts_at = parse_datetime(value[:starts_at] || value["starts_at"])
        ends_at = parse_datetime(value[:ends_at] || value["ends_at"])
        raise ArgumentError, "Unavailable time must end after it starts" unless ends_at > starts_at

        { developer_id: developer_id.to_s, starts_at: starts_at, ends_at: ends_at }
      end
    end

    def parse_datetime(value)
      value.respond_to?(:to_datetime) ? value.to_datetime : DateTime.parse(value.to_s)
    rescue Date::Error
      raise ArgumentError, "Invalid unavailable time"
    end

    def workday_start(date)
      DateTime.new(date.year, date.month, date.day, WORKDAY_START_HOUR)
    end

    def workday_end(date)
      DateTime.new(date.year, date.month, date.day, WORKDAY_END_HOUR)
    end

    def work_segments(initial_cursor, developer_id, hours)
      cursor = initial_cursor
      remaining_hours = hours
      segments = []

      while remaining_hours.positive?
        cursor = next_available_at(cursor, developer_id)
        available_until = next_unavailable_at(cursor, developer_id) || workday_end(cursor.to_date)
        available_until = [ available_until, workday_end(cursor.to_date) ].min
        available_hours = ((available_until - cursor) * 24).to_f
        assigned_hours = [ remaining_hours, available_hours ].min
        segment_end = cursor + Rational((assigned_hours * 3600).round, 86_400)

        segments << {
          "starts_at" => cursor.iso8601,
          "ends_at" => segment_end.iso8601
        }
        remaining_hours -= assigned_hours
        cursor = segment_end
      end

      segments
    end

    def next_available_at(value, developer_id)
      cursor = value

      loop do
        cursor = workday_start(next_workday(cursor.to_date)) if cursor.to_date.saturday? || cursor.to_date.sunday?
        cursor = workday_start(cursor.to_date) if cursor < workday_start(cursor.to_date)
        if cursor >= workday_end(cursor.to_date)
          cursor = workday_start(next_workday(cursor.to_date + 1))
          next
        end

        overlap = unavailable_for(developer_id).find do |period|
          period[:starts_at] <= cursor && period[:ends_at] > cursor
        end
        unless overlap
          return cursor
        end

        cursor = overlap[:ends_at]
      end
    end

    def next_unavailable_at(cursor, developer_id)
      unavailable_for(developer_id)
        .select { |period| period[:starts_at] > cursor && period[:starts_at].to_date == cursor.to_date }
        .map { |period| period[:starts_at] }
        .min
    end

    def unavailable_for(developer_id)
      @unavailability.select { |period| period[:developer_id] == developer_id }
    end

    def scheduling_labels_for(issue)
      names = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }
      {
        priority: names.find { |name| PRIORITY_RANKS.key?(name) },
        effort: names.find { |name| EFFORT_HOURS.key?(name) }
      }
    end

    def status_labels_for(issue)
      names = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }
      names.select { |name| STATUS_LABELS.key?(name) }
    end

    def status_for(issue)
      statuses = status_labels_for(issue).map { |label| STATUS_LABELS.fetch(label) }
      return "blocked" if statuses.include?("blocked")
      return "in_review" if statuses.include?("in_review")
      return "in_progress" if statuses.include?("in_progress")

      "backlog"
    end

    def classified_issues
      @issues.each_with_object([ [], [], [] ]) do |issue, groups|
        case status_for(issue)
        when "blocked" then groups[2] << issue
        when "in_review" then groups[1] << issue
        else groups[0] << issue
        end
      end
    end

    def serialize_informational(issue)
      labels = scheduling_labels_for(issue)
      status_labels = status_labels_for(issue)
      assignee = first_github_assignee(issue)

      serialize(issue).merge(
        "priority" => labels[:priority],
        "effort" => labels[:effort],
        "github_assignee_id" => assignee&.fetch("id", nil)&.to_s,
        "github_assignee_login" => assignee&.fetch("login", nil),
        "status_labels" => status_labels,
        "status_conflict" => status_labels.size > 1
      )
    end

    def preferred_developer_id_for(issue)
      assignee = first_github_assignee(issue)
      return unless assignee.is_a?(Hash)

      identifiers = [ assignee["id"], assignee["login"] ].compact.map(&:to_s)
      identifiers.each do |identifier|
        match = @developer_ids.find { |developer_id| developer_match?(developer_id, identifier) }
        return match if match
      end

      nil
    end

    def first_github_assignee(issue)
      Array(issue["assignees"]).first || issue["assignee"]
    end

    def developer_match?(developer_id, preferred_developer_id)
      preferred_developer_id && developer_id.casecmp?(preferred_developer_id)
    end

    def next_workday(date)
      date += 1 while date.saturday? || date.sunday?
      date
    end

    def parse_time(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.at(0)
    end

    def serialize(issue)
      repository = issue.fetch("repository_url").split("/").last(2).join("/")
      {
        "github_issue_id" => issue.fetch("github_issue_id", issue["id"]),
        "repository" => repository,
        "issue_number" => issue["number"],
        "title" => issue["title"],
        "url" => issue["html_url"]
      }
    end
  end
end
