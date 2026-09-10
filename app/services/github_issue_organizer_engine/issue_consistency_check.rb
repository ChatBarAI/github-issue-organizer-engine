module GithubIssueOrganizerEngine
  class IssueConsistencyCheck
    EXCLUSIVE_GROUPS = %w[Priority Effort Status].freeze

    def self.call(issues)
      issues.filter_map do |issue|
        next if issue.key?("pull_request")

        names = Array(issue["labels"]).map { |label| label.is_a?(Hash) ? label["name"] : label }.compact.uniq
        conflicts = EXCLUSIVE_GROUPS.to_h do |group|
          [ group, names.select { |name| name.match?(/\A#{group}:\s*\S/i) } ]
        end.select { |_group, labels| labels.size > 1 }
        { "issue" => issue, "conflicts" => conflicts } if conflicts.any?
      end
    end
  end
end
