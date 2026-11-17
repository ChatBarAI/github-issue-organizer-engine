require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/milestone_window"

module GithubIssueOrganizerEngine
  class MilestoneWindowTest < Minitest::Test
    def test_cutoff_uses_calendar_month_including_boundary_and_excluding_undated
      milestones = ["2026-02-27", "2026-02-28", "2026-03-01", nil].map { |date| { "due_on" => date } }
      assert_equal milestones[1..2], MilestoneWindow.call(milestones, starts_on: Date.new(2026, 3, 31))
    end
  end
end
