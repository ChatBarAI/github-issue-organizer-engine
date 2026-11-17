module GithubIssueOrganizerEngine
  class MilestoneGroups
    def self.call(milestones)
      milestones.group_by { |milestone| [milestone.fetch("title"), milestone.fetch("due_on")] }
        .values
        .map { |group| group.sort_by { |milestone| [milestone.fetch("repository"), milestone.fetch("id")] } }
        .sort_by { |group| [group.first.fetch("due_on"), group.first.fetch("title")] }
    end
  end
end
