require "test_helper"
require_relative "../../../app/helpers/github_issue_organizer_engine/timelines_helper"
require_relative "../../../app/services/github_issue_organizer_engine/issue_priority_counts"

module GithubIssueOrganizerEngine
  class TimelinesHelperTest < Minitest::Test
    include TimelinesHelper

    Snapshot = Struct.new(:captured_at, :priority_counts) do
      def total
        priority_counts.values.sum
      end
    end

    def test_chart_uses_elapsed_time_and_total_count_for_axes
      time = Time.utc(2026, 9, 1)
      snapshots = [0, 1, 4].map do |days|
        Snapshot.new(time + days.days, { "Priority: High" => 4, "No priority" => 6 })
      end
      series = issue_history_series(snapshots)

      assert_equal [60, 250, 820], series.first[:points].map { |point| point[:x] }
      assert_equal [40, 40, 40], series.first[:points].map { |point| point[:y] }
      assert_equal 6, series.size
    end

    def test_chart_handles_one_empty_snapshot
      series = issue_history_series([Snapshot.new(Time.current, IssuePriorityCounts.call([]))])
      assert series.all? { |entry| entry[:points].sole.values_at(:x, :y) == [440, 260] }
    end

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

    def test_prefers_a_users_full_name_for_timeline_attribution
      user = Struct.new(:fullname, :email).new("Ada Lovelace", "ada@example.test")

      assert_equal "Ada Lovelace", timeline_user_name(user, 7)
    end

    def test_falls_back_to_the_user_id_for_timeline_attribution
      assert_equal "User #7", timeline_user_name(nil, 7)
    end

    def test_labels_a_revision_draft_as_a_draft_edit
      timeline = Struct.new(:status, :source_timeline_id) do
        def draft?
          status == "draft"
        end
      end.new("draft", 12)

      assert_equal "Draft edit", timeline_status_label(timeline)
    end

    def test_keeps_an_original_draft_label
      timeline = Struct.new(:status, :source_timeline_id) do
        def draft?
          status == "draft"
        end
      end.new("draft", nil)

      assert_equal "Draft", timeline_status_label(timeline)
    end
  end
end
