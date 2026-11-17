require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/milestone_groups"

module GithubIssueOrganizerEngine
  class MilestoneGroupsTest < Minitest::Test
    def test_only_identical_titles_and_dates_are_grouped_regardless_of_state
      first = { "id" => "1", "repository" => "example/one", "title" => "Release", "due_on" => "2026-11-21", "state" => "open" }
      second = first.merge("id" => "2", "repository" => "example/two", "state" => "closed")
      later = first.merge("id" => "3", "due_on" => "2026-11-22")
      other = first.merge("id" => "4", "title" => "release")
      groups = MilestoneGroups.call([later, second, other, first])
      assert_equal [[first, second], [other], [later]], groups
    end
  end
end
