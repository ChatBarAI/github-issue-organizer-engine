require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/issue_priority_counts"

module GithubIssueOrganizerEngine
  class IssuePriorityCountsTest < Minitest::Test
    def test_counts_each_open_issue_once_at_its_highest_priority
      issues = [
        { "id" => 1, "labels" => [{ "name" => "Priority: Low" }, { "name" => "Priority: Critical" }] },
        { "id" => 2, "labels" => ["Status: Blocked"] },
        { "id" => 3, "labels" => ["Priority: High"] },
        { "id" => 4, "labels" => [], "pull_request" => {} },
        { "id" => 5, "labels" => [], "state" => "closed" }
      ]
      counts = IssuePriorityCounts.call(issues + [issues.first])

      assert_equal({ "Priority: Critical" => 1, "Priority: High" => 1,
        "Priority: Medium" => 0, "Priority: Low" => 0, "No priority" => 1 }, counts)
      assert_equal 3, counts.values.sum
    end

    def test_empty_snapshot_has_zero_for_every_priority
      assert_equal IssuePriorityCounts::PRIORITIES, IssuePriorityCounts.call([]).keys
      assert_equal [0], IssuePriorityCounts.call([]).values.uniq
    end
  end
end
