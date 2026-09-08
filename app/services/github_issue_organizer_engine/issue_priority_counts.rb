module GithubIssueOrganizerEngine
  class IssuePriorityCounts
    PRIORITIES = [ *Scheduler::PRIORITY_RANKS.keys, "No priority" ].freeze

    def self.call(issues)
      counts = PRIORITIES.index_with { 0 }
      issues.uniq { |issue| issue.fetch("id") }.each do |issue|
        next if issue.key?("pull_request") || issue["state"] == "closed"

        labels = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }
        priority = PRIORITIES.find { |name| labels.include?(name) } || "No priority"
        counts[priority] += 1
      end
      counts
    end
  end
end
