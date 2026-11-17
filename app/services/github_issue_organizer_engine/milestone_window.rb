module GithubIssueOrganizerEngine
  class MilestoneWindow
    def self.call(milestones, starts_on:)
      cutoff = starts_on.prev_month
      milestones.select do |milestone|
        milestone["due_on"].present? && Date.iso8601(milestone.fetch("due_on")) >= cutoff
      end
    end
  end
end
