require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_assignment_inheritor"

module GithubIssueOrganizerEngine
  class TimelineAssignmentInheritorTest < Minitest::Test
    FakeTimelineItem = Struct.new(
      :repository,
      :issue_number,
      :developer_id,
      :manually_assigned,
      keyword_init: true
    ) do
      alias_method :manually_assigned?, :manually_assigned
    end
    FakeTimeline = Struct.new(:items, keyword_init: true)

    def test_keeps_only_available_open_schedulable_manual_assignments
      timeline = FakeTimeline.new(items: [
        timeline_item(1, "developer-a"),
        timeline_item(2, "developer-a"),
        timeline_item(3, "developer-a"),
        timeline_item(4, "developer-a"),
        timeline_item(5, "removed-developer"),
        timeline_item(6, "developer-a", manually_assigned: false)
      ])
      issues = [
        issue(1),
        issue(2, state: "closed"),
        issue(3, effort: nil),
        issue(4, extra_labels: [ "Status: Blocked" ]),
        issue(5),
        issue(6),
        issue(7)
      ]

      result = TimelineAssignmentInheritor.new(
        issues: issues,
        timeline: timeline,
        developer_ids: [ "developer-a" ]
      ).call

      assert_equal 1, result.count
      assert_equal "developer-a", result.issues.first["assigned_developer_id"]
      assert_equal true, result.issues.first["manually_assigned"]
      result.issues.drop(1).each do |issue|
        refute issue.key?("assigned_developer_id"), "expected issue ##{issue.fetch("number")} not to inherit"
      end
    end

    def test_uses_the_canonical_developer_id_from_the_new_timeline
      timeline = FakeTimeline.new(items: [ timeline_item(1, "DEVELOPER-A") ])

      result = TimelineAssignmentInheritor.new(
        issues: [ issue(1) ],
        timeline: timeline,
        developer_ids: [ "developer-a" ]
      ).call

      assert_equal "developer-a", result.issues.first["assigned_developer_id"]
    end

    private

    def timeline_item(number, developer_id, manually_assigned: true)
      FakeTimelineItem.new(
        repository: "example/repo",
        issue_number: number,
        developer_id: developer_id,
        manually_assigned: manually_assigned
      )
    end

    def issue(number, state: "open", effort: "Effort: 1 day", extra_labels: [])
      labels = [ "Priority: High", effort, *extra_labels ].compact
      {
        "id" => number * 10,
        "number" => number,
        "repository_url" => "https://api.github.com/repos/example/repo",
        "state" => state,
        "labels" => labels.map { |name| { "name" => name } }
      }
    end
  end
end
