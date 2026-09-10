module GithubIssueOrganizerEngine
  class TimelineProgressInheritor
    def initialize(issues:, timeline:, starts_on:)
      @issues = issues
      @timeline = timeline
      @starts_on = Date.parse(starts_on.to_s)
    end

    def call
      return @issues unless @timeline

      items = @timeline.items.index_by { |item| [ item.repository, item.issue_number.to_i ] }
      @issues.map do |issue|
        labels = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }
        next issue unless issue.fetch("state", "open").casecmp?("open") &&
          labels.include?("Status: In-progress") &&
          (labels & [ "Status: Blocked", "Status: Review" ]).empty?

        repository = issue.fetch("repository_url").split("/").last(2).join("/")
        item = items[[ repository, issue.fetch("number").to_i ]]
        next issue unless item && item.starts_on < @starts_on

        issue.merge(
          "carried_starts_on" => item.starts_on.iso8601,
          "carried_work_segments" => Array(item.work_segments),
          "carried_developer_id" => item.developer_id
        )
      end
    end
  end
end
