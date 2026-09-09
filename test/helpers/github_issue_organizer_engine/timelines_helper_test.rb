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

      assert_equal [40, 225, 780], series.first[:points].map { |point| point[:x] }
      assert_equal [20, 20, 20], series.first[:points].map { |point| point[:y] }
      assert_equal 6, series.size
    end

    def test_chart_handles_one_empty_snapshot
      series = issue_history_series([Snapshot.new(Time.current, IssuePriorityCounts.call([]))])
      assert series.all? { |entry| entry[:points].sole.values_at(:x, :y) == [410, 170] }
    end

    def test_priority_areas_stack_to_total_without_counting_total_twice
      counts = IssuePriorityCounts.call([]).merge("Priority: High" => 4, "No priority" => 6)
      series = issue_history_series([Snapshot.new(Time.current, counts)])

      assert_nil series.first[:area]
      areas = series.drop(1).map { |entry| entry[:area] }
      assert_equal 170, areas.first[:polygon].last[:y]
      areas.each_cons(2) do |lower, upper|
        assert_equal lower[:top].first, upper[:polygon].last
      end
      assert_equal series.first[:points].first[:y], areas.last[:top].first[:y]
      assert_equal 4, series.find { |entry| entry[:label] == "High" }[:points].first[:count]
    end

    def test_axis_ticks_follow_elapsed_time_when_snapshots_cluster_at_the_end
      time = Time.utc(2026, 9, 8, 10)
      snapshots = [0, 23.hours, 24.hours].map { |offset| Snapshot.new(time + offset, {}) }
      ticks = issue_history_ticks(snapshots)

      assert_equal [40, 225, 410, 595, 780], ticks.map { |tick| tick[:x] }
      assert_equal [0, 6, 12, 18, 24].map { |hours| time + hours.hours }, ticks.map { |tick| tick[:captured_at] }
      assert_equal ["start", "middle", "middle", "middle", "end"], ticks.map { |tick| tick[:anchor] }
    end

    def test_axis_uses_one_centered_tick_for_identical_snapshot_times
      time = Time.utc(2026, 9, 8, 10)
      assert_equal [{ x: 410, captured_at: time, anchor: "middle" }],
        issue_history_ticks([Snapshot.new(time, {}), Snapshot.new(time, {})])
      assert_empty issue_history_ticks([])
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
