require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/issue_consistency_check"

module GithubIssueOrganizerEngine
  class IssueConsistencyCheckTest < Minitest::Test
    def test_reports_every_conflicting_exclusive_group_including_custom_values
      issue = { "labels" => ["Priority: High", "Priority: Low", "Effort: Small", "Effort: Large",
        "Status: Backlog", "Status: Review"].map { |name| { "name" => name } } }
      result = IssueConsistencyCheck.call([issue]).sole
      assert_equal issue, result.fetch("issue")
      assert_equal %w[Priority Effort Status], result.fetch("conflicts").keys
      assert_equal ["Effort: Small", "Effort: Large"], result.fetch("conflicts").fetch("Effort")
    end

    def test_ignores_missing_labels_duplicates_nonexclusive_groups_and_pull_requests
      issues = [
        { "labels" => ["Priority: High", "Priority: High", "Team: Client", "Team: Product", "WorkType: Bug", "WorkType: Feature"] },
        { "labels" => [] },
        { "labels" => ["Priority: High", "Priority: Low"], "pull_request" => {} }
      ]
      assert_empty IssueConsistencyCheck.call(issues)
    end
  end
end
