require_relative "../../test_helper"

module GithubIssueOrganizerEngine
  class SchedulerTest < Minitest::Test
    def test_orders_by_priority_and_skips_weekends
      result = Scheduler.new(
        issues: [
          issue(2, "Priority: High", "Effort: 4 hrs", "2026-01-01T00:00:00Z"),
          issue(1, "Priority: Critical", "Effort: 2 days", "2026-02-01T00:00:00Z"),
          issue(3, "Priority: High", "Effort: 4 hrs", "2026-03-01T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      ).call

      assert_equal [ 1, 2, 3 ], result.scheduled.map { |item| item["issue_number"] }
      assert_equal "2026-08-28", result.scheduled.first["starts_on"]
      assert_equal "2026-08-31", result.scheduled.first["ends_on"]
      assert_equal "2026-09-01", result.scheduled.second["starts_on"]
      assert_equal "2026-09-01", result.scheduled.third["starts_on"]
      assert_equal 24, result.total_hours
      assert_equal "2026-09-01", result.ends_on
    end

    def test_separates_issues_missing_required_labels
      result = Scheduler.new(
        issues: [ issue(4, "Priority: Low", nil, "2026-01-01T00:00:00Z") ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      ).call

      assert_empty result.scheduled
      assert_nil result.ends_on
      assert_equal [ "effort" ], result.needs_labels.first["missing"]
    end

    def test_lists_review_and_blocked_issues_without_allocating_capacity
      review = issue(1, "Priority: High", "Effort: 2 days", "2026-01-01T00:00:00Z")
      review["labels"] << { "name" => "Status: Review" }
      blocked = issue(2, "Priority: Critical", "Effort: 5 days", "2026-01-02T00:00:00Z")
      blocked["labels"] << { "name" => "Status: Blocked" }

      result = Scheduler.new(
        issues: [ review, blocked ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      ).call

      assert_empty result.scheduled
      assert_equal [ 1 ], result.in_review.map { |item| item["issue_number"] }
      assert_equal [ 2 ], result.blocked.map { |item| item["issue_number"] }
      assert_equal 0, result.total_hours
      assert_nil result.ends_on
    end

    def test_blocked_takes_precedence_and_reports_conflicting_status_labels
      issue_with_conflict = issue(1, "Priority: High", nil, "2026-01-01T00:00:00Z")
      issue_with_conflict["labels"].concat([
        { "name" => "Status: Review" },
        { "name" => "Status: Blocked" }
      ])

      result = Scheduler.new(
        issues: [ issue_with_conflict ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      ).call

      assert_empty result.in_review
      assert_empty result.needs_labels
      assert_equal true, result.blocked.first["status_conflict"]
      assert_equal [ "Status: Review", "Status: Blocked" ], result.blocked.first["status_labels"]
    end

    def test_schedules_in_progress_before_unstarted_work_at_the_same_priority
      backlog = issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z")
      backlog["labels"] << { "name" => "Status: Backlog" }
      in_progress = issue(2, "Priority: High", "Effort: 1 day", "2026-02-01T00:00:00Z")
      in_progress["labels"] << { "name" => "Status: In-progress" }

      result = Scheduler.new(
        issues: [ backlog, in_progress ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      ).call

      assert_equal [ 2, 1 ], result.scheduled.map { |item| item["issue_number"] }
      assert_equal 16, result.total_hours
    end

    def test_review_and_blocked_issues_do_not_trigger_manual_ranking
      issues = (1..3).map do |number|
        issue(number, "Priority: High", "Effort: 1 day", "2026-01-0#{number}T00:00:00Z").tap do |value|
          value["labels"] << { "name" => number.odd? ? "Status: Review" : "Status: Blocked" }
        end
      end

      scheduler = Scheduler.new(
        issues: issues,
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      )

      assert_empty scheduler.tie_groups
    end

    def test_schedules_issues_in_parallel_across_available_developers
      result = Scheduler.new(
        issues: [
          issue(1, "Priority: Critical", "Effort: 2 days", "2026-01-01T00:00:00Z"),
          issue(2, "Priority: High", "Effort: 1 day", "2026-01-02T00:00:00Z"),
          issue(3, "Priority: Medium", "Effort: 1 day", "2026-01-03T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b" ]
      ).call

      assert_equal 2, result.developer_count
      assert_equal [ "developer-a", "developer-b", "developer-b" ],
        result.scheduled.map { |item| item["developer_id"] }
      assert_equal [ 1, 2, 2 ], result.scheduled.map { |item| item["developer_position"] }
      assert_equal [ "2026-08-28", "2026-08-28", "2026-08-31" ],
        result.scheduled.map { |item| item["starts_on"] }
      assert_equal "2026-08-31", result.scheduled.first["ends_on"]
    end

    def test_prefers_the_first_github_assignee_when_developers_are_equally_available
      assigned_issue = issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z")
      assigned_issue["assignees"] = [ { "id" => 202, "login" => "developer-c" } ]

      result = Scheduler.new(
        issues: [ assigned_issue ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "202", "developer-c" ]
      ).call

      assert_equal "202", result.scheduled.first["developer_id"]
      assert result.scheduled.first["github_assignee_matches"]
      assert_equal "202", result.scheduled.first["github_assignee_id"]
      assert_equal "developer-c", result.scheduled.first["github_assignee_login"]
    end

    def test_does_not_prefer_the_github_assignee_over_an_earlier_available_developer
      assigned_issue = issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z")
      assigned_issue["assignees"] = [ { "login" => "developer-b" } ]

      result = Scheduler.new(
        issues: [ assigned_issue ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b" ],
        unavailability: [
          {
            developer_id: "developer-b",
            starts_at: "2026-08-28T09:00:00+00:00",
            ends_at: "2026-08-28T10:00:00+00:00"
          }
        ]
      ).call

      assert_equal "developer-a", result.scheduled.first["developer_id"]
      refute result.scheduled.first["github_assignee_matches"]
    end

    def test_assigns_to_the_developer_who_will_complete_the_issue_first
      short_pinned_issue = issue(1, "Priority: Critical", "Effort: 4 hrs", "2026-01-01T00:00:00Z")
        .merge("assigned_developer_id" => "developer-b")

      result = Scheduler.new(
        issues: [
          short_pinned_issue,
          issue(2, "Priority: High", "Effort: 5 days", "2026-01-02T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 31),
        developer_ids: [ "developer-a", "developer-b" ],
        unavailability: [
          {
            developer_id: "developer-a",
            starts_at: "2026-09-01T09:00:00+00:00",
            ends_at: "2026-09-03T09:00:00+00:00"
          }
        ]
      ).call

      long_issue = result.scheduled.last
      assert_equal "developer-b", long_issue["developer_id"]
      assert_equal "2026-09-07", long_issue["ends_on"]
    end

    def test_ignores_later_github_assignees
      assigned_issue = issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z")
      assigned_issue["assignees"] = [
        { "login" => "external-developer" },
        { "login" => "developer-b" }
      ]

      result = Scheduler.new(
        issues: [ assigned_issue ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b" ]
      ).call

      assert_equal "developer-a", result.scheduled.first["developer_id"]
    end

    def test_exposes_same_priority_issues_for_user_ranking
      scheduler = Scheduler.new(
        issues: [
          issue(2, "Priority: High", "Effort: 1 day", "2026-02-01T00:00:00Z"),
          issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z"),
          issue(3, "Priority: Low", "Effort: 1 day", "2026-03-01T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ]
      )

      assert_equal [ "Priority: High" ], scheduler.tie_groups.map { |group| group["priority"] }
      assert_equal [ "10", "20" ], scheduler.tie_groups.first["issues"].map { |item| item["id"] }
      assert_equal [ "Effort: 1 day", "Effort: 1 day" ],
        scheduler.tie_groups.first["issues"].map { |item| item["effort"] }
      assert_equal [ 8, 8 ], scheduler.tie_groups.first["issues"].map { |item| item["effort_hours"] }
    end

    def test_does_not_request_ranking_when_developers_cover_the_priority_group
      scheduler = Scheduler.new(
        issues: [
          issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z"),
          issue(2, "Priority: High", "Effort: 1 day", "2026-02-01T00:00:00Z"),
          issue(3, "Priority: High", "Effort: 1 day", "2026-03-01T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b", "developer-c" ]
      )

      assert_empty scheduler.tie_groups
    end

    def test_requests_ranking_when_priority_group_exceeds_developer_capacity
      scheduler = Scheduler.new(
        issues: [
          issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z"),
          issue(2, "Priority: High", "Effort: 1 day", "2026-02-01T00:00:00Z"),
          issue(3, "Priority: High", "Effort: 1 day", "2026-03-01T00:00:00Z"),
          issue(4, "Priority: High", "Effort: 1 day", "2026-04-01T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b", "developer-c" ]
      )

      assert_equal [ "10", "20", "30", "40" ],
        scheduler.tie_groups.first["issues"].map { |item| item["id"] }
    end

    def test_uses_explicit_order_within_a_priority
      result = Scheduler.new(
        issues: [
          issue(1, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z"),
          issue(2, "Priority: High", "Effort: 1 day", "2026-02-01T00:00:00Z"),
          issue(3, "Priority: Critical", "Effort: 1 day", "2026-03-01T00:00:00Z")
        ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ],
        ordered_issue_ids: [ "20", "10" ]
      ).call

      assert_equal [ 3, 2, 1 ], result.scheduled.map { |item| item["issue_number"] }
    end

    def test_strict_issue_order_preserves_a_manually_edited_developer_queue
      low_priority = issue(1, "Priority: Low", "Effort: 1 day", "2026-01-01T00:00:00Z")
      low_priority["assigned_developer_id"] = "developer-a"
      critical = issue(2, "Priority: Critical", "Effort: 1 day", "2026-01-02T00:00:00Z")
      critical["assigned_developer_id"] = "developer-a"

      result = Scheduler.new(
        issues: [ low_priority, critical ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ],
        ordered_issue_ids: [ "10", "20" ],
        strict_issue_order: true
      ).call

      assert_equal [ 1, 2 ], result.scheduled.map { |item| item["issue_number"] }
      assert_equal [ "2026-08-28", "2026-08-31" ], result.scheduled.map { |item| item["starts_on"] }
      assert_equal [ "developer-a", "developer-a" ], result.scheduled.map { |item| item["developer_id"] }
    end

    def test_rejects_an_empty_developer_id_list
      error = assert_raises(ArgumentError) do
        Scheduler.new(issues: [], starts_on: Date.new(2026, 8, 28), developer_ids: [])
      end

      assert_equal "Configure between 1 and 100 developer IDs in Settings", error.message
    end

    def test_splits_an_issue_around_unavailable_hours
      result = Scheduler.new(
        issues: [ issue(1, "Priority: Critical", "Effort: 1 day", "2026-01-01T00:00:00Z") ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a" ],
        unavailability: [
          {
            developer_id: "developer-a",
            starts_at: "2026-08-28T12:00:00+00:00",
            ends_at: "2026-08-28T14:00:00+00:00"
          }
        ]
      ).call

      item = result.scheduled.first
      assert_equal "2026-08-31", item["ends_on"]
      assert_equal [
        [ "2026-08-28T09:00:00+00:00", "2026-08-28T12:00:00+00:00" ],
        [ "2026-08-28T14:00:00+00:00", "2026-08-28T17:00:00+00:00" ],
        [ "2026-08-31T09:00:00+00:00", "2026-08-31T11:00:00+00:00" ]
      ], item["work_segments"].map { |segment| segment.values_at("starts_at", "ends_at") }
    end

    def test_keeps_an_existing_developer_assignment_when_rescheduling_around_unavailability
      pinned_issue = issue(1, "Priority: Critical", "Effort: 1 day", "2026-01-01T00:00:00Z")
        .merge("assigned_developer_id" => "developer-a", "manually_assigned" => true)

      result = Scheduler.new(
        issues: [ pinned_issue ],
        starts_on: Date.new(2026, 8, 28),
        developer_ids: [ "developer-a", "developer-b" ],
        unavailability: [
          {
            developer_id: "developer-a",
            starts_at: "2026-08-28T09:00:00+00:00",
            ends_at: "2026-08-28T17:00:00+00:00"
          }
        ]
      ).call

      item = result.scheduled.first
      assert_equal "developer-a", item["developer_id"]
      assert_equal true, item["manually_assigned"]
      assert_equal "2026-08-31", item["starts_on"]
      assert_equal 1, result.scheduled.size
    end

    def test_partial_order_places_ranked_issues_first_and_others_by_creation_date
      issues = [
        issue(1, "Priority: High", "Effort: 1 day", "2026-01-02T00:00:00Z"),
        issue(2, "Priority: High", "Effort: 1 day", "2026-01-01T00:00:00Z"),
        issue(3, "Priority: High", "Effort: 1 day", "2026-01-03T00:00:00Z"),
        issue(4, "Priority: Critical", "Effort: 1 day", "2026-01-04T00:00:00Z")
      ]
      result = Scheduler.new(issues: issues, starts_on: "2026-09-10",
        developer_ids: ["alice"], ordered_issue_ids: [30]).call
      assert_equal [4, 3, 2, 1], result.scheduled.map { |item| item["issue_number"] }
    end

    private

    def issue(number, priority, effort, created_at)
      labels = [ priority, effort ].compact.map { |name| { "name" => name } }
      {
        "id" => number * 10,
        "number" => number,
        "title" => "Issue #{number}",
        "html_url" => "https://github.com/example/repo/issues/#{number}",
        "repository_url" => "https://api.github.com/repos/example/repo",
        "created_at" => created_at,
        "labels" => labels
      }
    end
  end
end
