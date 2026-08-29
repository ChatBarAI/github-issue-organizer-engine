module GithubIssueOrganizerEngine
  class TimelineAssignmentInheritor
    Result = Struct.new(:issues, :count, keyword_init: true)

    def initialize(issues:, timeline:, developer_ids:)
      @issues = issues
      @timeline = timeline
      @developer_ids = developer_ids
    end

    def call
      assignments = inherited_assignments
      count = 0
      issues = @issues.map do |issue|
        assignment = assignments[issue_key(issue)]
        next issue unless assignment && open?(issue) && schedulable?(issue)

        count += 1
        issue.merge(
          "assigned_developer_id" => assignment,
          "manually_assigned" => true
        )
      end

      Result.new(issues: issues, count: count)
    end

    private

    def inherited_assignments
      return {} unless @timeline

      @timeline.items.each_with_object({}) do |item, assignments|
        next unless item.manually_assigned?

        developer_id = @developer_ids.find { |candidate| candidate.casecmp?(item.developer_id) }
        assignments[[ item.repository, item.issue_number.to_i ]] = developer_id if developer_id
      end
    end

    def issue_key(issue)
      repository = issue.fetch("repository_url").split("/").last(2).join("/")
      [ repository, issue.fetch("number").to_i ]
    end

    def open?(issue)
      issue.fetch("state", "open").casecmp?("open")
    end

    def schedulable?(issue)
      labels = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }
      has_priority = labels.any? { |label| Scheduler::PRIORITY_RANKS.key?(label) }
      has_effort = labels.any? { |label| Scheduler::EFFORT_HOURS.key?(label) }
      unavailable_status = labels.any? { |label| %w[Status:\ Blocked Status:\ Review].include?(label) }
      has_priority && has_effort && !unavailable_status
    end
  end
end
