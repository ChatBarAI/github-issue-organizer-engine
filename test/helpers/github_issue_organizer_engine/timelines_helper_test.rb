require "test_helper"
require_relative "../../../app/helpers/github_issue_organizer_engine/timelines_helper"

module GithubIssueOrganizerEngine
  class TimelinesHelperTest < Minitest::Test
    include TimelinesHelper

    def test_formats_a_single_day_once
      assert_equal "August 29, 2026", compact_date_range(Date.new(2026, 8, 29), Date.new(2026, 8, 29))
    end

    def test_avoids_repeating_a_shared_month_and_year
      assert_equal "August 29–31, 2026", compact_date_range(Date.new(2026, 8, 29), Date.new(2026, 8, 31))
    end

    def test_avoids_repeating_a_shared_year
      assert_equal "August 31 – September 8, 2026",
        compact_date_range(Date.new(2026, 8, 31), Date.new(2026, 9, 8))
    end

    def test_includes_both_years_when_they_differ
      assert_equal "December 31, 2026 – January 2, 2027",
        compact_date_range(Date.new(2026, 12, 31), Date.new(2027, 1, 2))
    end
  end
end
