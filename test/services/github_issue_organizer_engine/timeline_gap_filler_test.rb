require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_gap_filler"

module GithubIssueOrganizerEngine
  class TimelineGapFillerTest < Minitest::Test
    Item = Struct.new(:id, :repository, :issue_number, :title, :url, :priority,
      :effort_hours, :developer_id, :starts_on, :ends_on, :work_segments, :position,
      :manually_assigned, keyword_init: true) do
      def update!(attributes)
        attributes.each { |key, value| public_send("#{key}=", value) }
      end
    end
    Timeline = Struct.new(:items, :developer_ids, :unavailabilities, :starts_on, keyword_init: true) do
      def transaction
        yield
      end
    end

    def test_cutoff_preserves_spanning_work_and_assignments_and_current_queue_order
      fixed = item(1, "a", "2026-09-10", 8)
      fixed.ends_on = Date.new(2026, 9, 14)
      fixed.work_segments << {"starts_at" => "2026-09-14T09:00:00+00:00", "ends_at" => "2026-09-14T13:00:00+00:00"}
      first = item(3, "a", "2026-09-15", 4)
      second = item(2, "a", "2026-09-16", 8)
      other = item(4, "b", "2026-09-11", 4)
      timeline = timeline([fixed, second, first, other])
      original = fixed.to_h.deep_dup
      TimelineGapFiller.new(timeline: timeline, from_date: "2026-09-11").call
      assert_equal original, fixed.to_h
      assert_equal "2026-09-14T13:00:00+00:00", first.work_segments.first["starts_at"]
      assert_equal Date.new(2026, 9, 15), second.starts_on
      assert_equal Date.new(2026, 9, 11), other.starts_on
      assert_equal ["a", "a", "b"], [first, second, other].map(&:developer_id)
      assert_equal [3, 2, 4], [first, second, other].map(&:position)
      assert first.manually_assigned
      assert_equal Date.new(2026, 9, 1), timeline.starts_on
      snapshot = timeline.items.map { |entry| entry.to_h.deep_dup }
      TimelineGapFiller.new(timeline: timeline, from_date: "2026-09-11").call
      assert_equal snapshot, timeline.items.map(&:to_h)
    end

    def test_skips_weekends_and_unavailable_hours
      moving = item(1, "a", "2026-09-16", 8)
      timeline = timeline([moving])
      period = Struct.new(:developer_id, :starts_at, :ends_at)
      timeline.unavailabilities << period.new("a", "2026-09-14T09:00:00+00:00", "2026-09-14T13:00:00+00:00")
      TimelineGapFiller.new(timeline: timeline, from_date: "2026-09-12").call
      assert_equal "2026-09-14T13:00:00+00:00", moving.work_segments.first["starts_at"]
      assert_equal "2026-09-15T13:00:00+00:00", moving.work_segments.last["ends_at"]
    end

    def test_invalid_date_and_no_eligible_work
      fixed = item(1, "a", "2026-09-10", 8)
      timeline = timeline([fixed])
      assert_raises(ArgumentError) { TimelineGapFiller.new(timeline: timeline, from_date: "invalid").call }
      snapshot = fixed.to_h.deep_dup
      TimelineGapFiller.new(timeline: timeline, from_date: "2026-09-20").call
      assert_equal snapshot, fixed.to_h
    end

    private

    def timeline(items)
      Timeline.new(items: items, developer_ids: ["a", "b"], unavailabilities: [], starts_on: Date.new(2026, 9, 1))
    end

    def item(id, developer, date, hours)
      Item.new(id: id, repository: "org/repo", issue_number: id, title: "Issue #{id}",
        url: "https://example.com/#{id}", priority: "Priority: Medium", effort_hours: hours,
        developer_id: developer, starts_on: Date.iso8601(date), ends_on: Date.iso8601(date),
        position: id, manually_assigned: true,
        work_segments: [{"starts_at" => "#{date}T09:00:00+00:00", "ends_at" => "#{date}T#{9 + hours}:00:00+00:00"}])
    end
  end
end
