require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/milestone_forecast"

module GithubIssueOrganizerEngine
  class MilestoneForecastTest < Minitest::Test
    Item = Struct.new(:repository, :issue_number, :ends_on)

    def setup
      @today = Date.new(2026, 11, 17)
      @milestone = { "repository" => "example/one", "due_on" => "2026-11-21",
        "issues" => [{ "number" => 1, "state" => "open" }] }
    end

    def forecast(milestones = [@milestone], items = [])
      MilestoneForecast.new(items: items, today: @today).call(milestones)
    end

    def test_all_issues_must_finish_by_due_date_across_every_repository
      other = @milestone.merge("repository" => "example/two")
      one = Item.new("EXAMPLE/ONE", 1, Date.new(2026, 11, 21))
      two = Item.new("example/two", 1, Date.new(2026, 11, 20))
      assert_equal :on_track, forecast([@milestone, other], [one, two]).status
      assert_equal :uncertain, forecast([@milestone, other], [one]).status
      two.ends_on = Date.new(2026, 11, 22)
      assert_equal :late, forecast([@milestone, other], [one, two]).status
      assert_includes forecast([@milestone, other], [two]).detail, "example/two#1"
    end

    def test_unplanned_or_unfinished_issues_are_not_assumed_complete
      assert_equal :uncertain, forecast.status
      item = Item.new("example/one", 1, nil)
      assert_equal :uncertain, forecast([@milestone], [item]).status
      item.ends_on = @today - 1
      assert_equal :uncertain, forecast([@milestone], [item]).status
      @milestone["due_on"] = (@today - 1).iso8601
      assert_equal :late, forecast([@milestone], [item]).status
    end

    def test_closed_issues_are_checked_against_actual_completion_dates
      @milestone["issues"] = [{ "number" => 1, "state" => "closed", "closed_on" => "2026-11-21" }]
      assert_equal :on_track, forecast.status
      assert_equal "Completed on time", forecast.label
      @milestone["issues"].first["closed_on"] = "2026-11-22"
      assert_equal :late, forecast.status
      @milestone["issues"].first["closed_on"] = nil
      assert_equal :uncertain, forecast.status
    end

    def test_missing_snapshot_or_empty_milestone_is_uncertain
      assert_equal :uncertain, forecast([@milestone.except("issues")]).status
      @milestone["issues"] = []
      assert_equal :uncertain, forecast.status
    end

    def test_lateness_takes_priority_over_missing_data
      missing = @milestone.except("issues").merge("repository" => "example/two")
      item = Item.new("example/one", 1, Date.new(2026, 11, 22))
      result = forecast([@milestone, missing], [item])
      assert_equal :late, result.status
      assert_includes result.detail, "issue status has not been checked"
    end

    def test_issue_details_keep_every_issue_and_show_the_most_urgent_first
      @milestone["issues"] = (1..7).map { |number| { "number" => number, "state" => "open", "title" => "Task #{number}" } }
      planned = Item.new("example/one", 1, Date.new(2026, 11, 20))
      late = Item.new("example/one", 2, Date.new(2026, 11, 22))
      calculator = MilestoneForecast.new(items: [planned, late], today: @today)
      details = calculator.issue_details([@milestone])
      assert_equal 7, details.size
      assert_equal 2, details.first.number
      assert_equal :late, details.first.forecast.status
      assert_equal "Task 2", details.first.title
      assert_equal late.ends_on, details.first.ends_on
      assert_equal :on_track, details.last.forecast.status
      assert_equal 5, details.count { |issue| issue.forecast.status == :uncertain }
      assert_equal "example/one", details.first.repository
    end

    def test_issue_details_support_older_snapshots_and_closed_dates
      @milestone["issues"] = [{ "number" => 8, "state" => "closed", "closed_on" => "2026-11-20" }]
      details = MilestoneForecast.new(items: [], today: @today).issue_details([@milestone])
      assert_equal "Issue #8", details.first.title
      assert_equal Date.new(2026, 11, 20), details.first.closed_on
      assert_equal :on_track, details.first.forecast.status
      assert_empty MilestoneForecast.new(items: [], today: @today).issue_details([@milestone.except("issues")])
    end

    def test_forecast_changes_after_rescheduling_without_refetching_github
      item = Item.new("example/one", 1, Date.new(2026, 11, 21))
      calculator = MilestoneForecast.new(items: [item], today: @today)
      assert_equal :on_track, calculator.call([@milestone]).status
      item.ends_on += 1
      assert_equal :late, calculator.call([@milestone]).status
    end
  end
end
