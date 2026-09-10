require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_progress_inheritor"

module GithubIssueOrganizerEngine
  class TimelineProgressInheritorTest < Minitest::Test
    Item = Struct.new(:repository, :issue_number, :starts_on, :developer_id, :work_segments)
    CurrentTimeline = Struct.new(:items)

    def test_preserves_recorded_history_and_schedules_only_remaining_effort
      original = issue
      inherited = inherit([original])
      result = Scheduler.new(issues: inherited, starts_on: "2026-09-10", developer_ids: ["alice"]).call
      assert_equal "2026-09-03", result.scheduled.first.fetch("starts_on")
      assert_equal "2026-09-10", result.scheduled.first.fetch("ends_on")
      assert_equal "2026-09-03T09:00:00+00:00", result.scheduled.first.fetch("work_segments").first.fetch("starts_at")
      refute original.key?("carried_starts_on")
    end

    def test_ignores_closed_blocked_review_backlog_unmatched_and_future_issues
      issues = [
        issue.merge("state" => "closed"),
        issue.merge("labels" => ["Status: In-progress", "Status: Blocked"]),
        issue.merge("labels" => ["Status: In-progress", "Status: Review"]),
        issue.merge("labels" => ["Status: Backlog"]),
        issue.merge("number" => 2),
        issue.merge("repository_url" => "https://api.github.com/repos/other/repo")
      ]
      assert_equal issues, inherit(issues)
      assert_equal [issue], inherit([issue], start: "2026-09-03")
      assert_equal [issue], inherit([issue], start: "2026-09-02")
      assert_equal [issue], TimelineProgressInheritor.new(issues: [issue], timeline: nil, starts_on: "2026-09-10").call
    end

    def test_continues_existing_work_before_higher_priority_and_manually_ordered_work
      backlog = issue.merge(
        "id" => 2, "number" => 2,
        "assigned_developer_id" => "alice",
        "labels" => ["Priority: Critical", "Effort: 1 day"]
      )
      [false, true].each do |strict_order|
        result = Scheduler.new(
          issues: inherit([backlog, issue]), starts_on: "2026-09-10",
          developer_ids: ["bob", "alice"], ordered_issue_ids: [2, 1],
          strict_issue_order: strict_order
        ).call

        continuation, new_work = result.scheduled
        assert_equal 1, continuation.fetch("issue_number")
        assert_equal "alice", continuation.fetch("developer_id")
        assert_equal "2026-09-03T09:00:00+00:00", continuation.fetch("work_segments").first.fetch("starts_at")
        assert_equal "2026-09-10", new_work.fetch("starts_on")
      end
    end

    def test_can_continue_when_the_previous_developer_is_no_longer_available
      result = Scheduler.new(
        issues: inherit([issue]), starts_on: "2026-09-10", developer_ids: ["bob"]
      ).call
      assert_equal "bob", result.scheduled.first.fetch("developer_id")
      assert_equal "2026-09-03", result.scheduled.first.fetch("starts_on")
    end

    private

    def inherit(issues, start: "2026-09-10")
      TimelineProgressInheritor.new(
        issues: issues,
        timeline: CurrentTimeline.new([Item.new("example/repo", 1, Date.new(2026, 9, 3), "ALICE", [{"starts_at" => "2026-09-03T09:00:00+00:00", "ends_at" => "2026-09-03T13:00:00+00:00"}])]),
        starts_on: start
      ).call
    end

    def issue
      {
        "id" => 1, "number" => 1, "title" => "Work in progress",
        "repository_url" => "https://api.github.com/repos/example/repo",
        "labels" => ["Status: In-progress", "Priority: High", "Effort: 1 day"]
      }
    end
  end
end
