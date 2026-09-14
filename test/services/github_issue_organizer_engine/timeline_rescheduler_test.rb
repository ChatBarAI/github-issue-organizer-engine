require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_rescheduler"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_item_mover"

module GithubIssueOrganizerEngine
  class TimelineReschedulerTest < Minitest::Test
    FakeItem = Struct.new(
      :id,
      :github_issue_id,
      :repository,
      :issue_number,
      :title,
      :url,
      :github_assignee_id,
      :github_assignee_login,
      :developer_id,
      :priority,
      :effort_hours,
      :position,
      :starts_on,
      :ends_on,
      :work_segments,
      keyword_init: true
    ) do
      def update!(attributes)
        attributes.each { |name, value| public_send("#{name}=", value) if respond_to?("#{name}=") }
      end

      def reload
        self
      end
    end

    class FakeItems < Array
      attr_reader :update_statement

      def update_all(statement)
        @update_statement = statement
      end
    end

    FakeTimeline = Struct.new(:starts_on, :developer_ids, :items, :unavailabilities, keyword_init: true) do
      def transaction
        yield
      end

      def update!(starts_on:)
        self.starts_on = starts_on
      end
    end

    def test_moves_existing_positions_out_of_the_way_for_every_reschedule
      items = FakeItems.new([
        fake_item(id: 1, issue_number: 11, position: 1),
        fake_item(id: 2, issue_number: 22, position: 2)
      ])
      timeline = FakeTimeline.new(
        starts_on: Date.new(2026, 8, 29),
        developer_ids: [ "developer-a" ],
        items: items,
        unavailabilities: []
      )
      scheduler = Object.new
      scheduler.define_singleton_method(:call) { Struct.new(:scheduled).new([]) }

      Scheduler.stub(:new, ->(**) { scheduler }) do
        TimelineRescheduler.new(timeline: timeline).call
      end

      assert_equal "position = position + 2", items.update_statement
    end

    def test_keeps_carried_start_dates_when_rescheduling
      item = fake_item(id: 1, issue_number: 11, position: 1)
      item.starts_on = Date.new(2026, 8, 24)
      item.work_segments = [{"starts_at" => "2026-08-24T09:00:00+00:00", "ends_at" => "2026-08-24T11:00:00+00:00"}]
      timeline = FakeTimeline.new(
        starts_on: Date.new(2026, 8, 31), developer_ids: ["developer-a"],
        items: FakeItems.new([item]), unavailabilities: []
      )

      TimelineRescheduler.new(timeline: timeline, starts_on: Date.new(2026, 9, 1)).call

      assert_equal "2026-08-24", item.starts_on
    end

    def test_advancing_boundary_and_repeated_edits_preserve_hours
      item = fake_item(id: 1, issue_number: 50, position: 1)
      item.work_segments = [{"starts_at" => "2026-08-31T09:00:00+00:00", "ends_at" => "2026-08-31T11:00:00+00:00"}]
      timeline = FakeTimeline.new(starts_on: Date.new(2026, 8, 31),
        developer_ids: ["developer-a"], items: FakeItems.new([item]), unavailabilities: [])
      TimelineRescheduler.new(timeline: timeline, starts_on: Date.new(2026, 9, 1)).call
      first_segments = item.work_segments.deep_dup
      assert_equal "2026-09-01T11:00:00+00:00", first_segments.last["ends_at"]
      # ActiveRecord casts persisted dates back to Date values.
      item.starts_on = Date.parse(item.starts_on)
      TimelineRescheduler.new(timeline: timeline).call
      assert_equal first_segments, item.work_segments
    end

    def test_recalculates_stale_dates_after_preceding_work_was_shortened
      preceding = fake_item(id: 1, issue_number: 50, position: 1)
      preceding.effort_hours = 40
      preceding.starts_on = Date.new(2026, 9, 8)
      preceding.work_segments = (8..10).map do |day|
        date = "2026-09-#{day.to_s.rjust(2, '0')}"
        {"starts_at" => "#{date}T09:00:00+00:00", "ends_at" => "#{date}T17:00:00+00:00"}
      end
      moving = fake_item(id: 2, issue_number: 49, position: 2)
      moving.effort_hours = 40
      moving.starts_on = Date.new(2026, 9, 21)
      timeline = FakeTimeline.new(starts_on: Date.new(2026, 9, 11),
        developer_ids: ["developer-a"], items: FakeItems.new([preceding, moving]), unavailabilities: [])

      TimelineRescheduler.new(timeline: timeline, allow_reassignment: false, ordered_item_ids: [1, 2]).call

      assert_equal "2026-09-14", preceding.ends_on
      assert_equal "2026-09-15", moving.starts_on
      assert_equal "2026-09-21", moving.ends_on
    end

    def test_inserts_urgent_work_before_a_continuation_and_preserves_the_order_on_later_moves
      ongoing = fake_item(id: 1, issue_number: 11, position: 1)
      ongoing.effort_hours = 16
      ongoing.starts_on = Date.new(2026, 9, 10)
      history = {"starts_at" => "2026-09-10T09:00:00+00:00", "ends_at" => "2026-09-10T17:00:00+00:00"}
      ongoing.work_segments = [history,
        {"starts_at" => "2026-09-11T09:00:00+00:00", "ends_at" => "2026-09-11T17:00:00+00:00"}]
      urgent = fake_item(id: 2, issue_number: 22, position: 2)
      following = fake_item(id: 3, issue_number: 33, position: 3)
      urgent.starts_on = following.starts_on = Date.new(2026, 9, 14)
      timeline = FakeTimeline.new(starts_on: Date.new(2026, 9, 11),
        developer_ids: ["developer-a"], items: FakeItems.new([ongoing, urgent, following]), unavailabilities: [])

      TimelineItemMover.new(timeline: timeline, item: urgent, developer_id: "developer-a", before_item_id: ongoing.id).call

      assert_equal "2026-09-11T09:00:00+00:00", urgent.work_segments.first.fetch("starts_at")
      assert_equal "2026-09-11T13:00:00+00:00", ongoing.work_segments[1].fetch("starts_at")
      assert_equal history, ongoing.work_segments.first
      assert_equal 16, hours_in(ongoing.work_segments)

      # ActiveRecord casts the dates written by the rescheduler.
      timeline.items.each { |item| item.starts_on = Date.parse(item.starts_on) }
      TimelineItemMover.new(timeline: timeline, item: following, developer_id: "developer-a", before_item_id: ongoing.id).call

      assert_equal "2026-09-11T09:00:00+00:00", urgent.work_segments.first.fetch("starts_at")
      assert_equal "2026-09-11T13:00:00+00:00", following.work_segments.first.fetch("starts_at")
      assert_equal "2026-09-14T09:00:00+00:00", ongoing.work_segments[1].fetch("starts_at")
      assert_equal history, ongoing.work_segments.first
      assert_equal 16, hours_in(ongoing.work_segments)
      assert_equal [2, 3, 1], timeline.items.sort_by(&:position).map(&:id)
    end

    private

    def hours_in(segments)
      segments.sum do |segment|
        (DateTime.iso8601(segment.fetch("ends_at")) - DateTime.iso8601(segment.fetch("starts_at"))) * 24
      end
    end

    def fake_item(id:, issue_number:, position:)
      FakeItem.new(
        id: id,
        github_issue_id: id + 100,
        repository: "example/repository",
        issue_number: issue_number,
        title: "Issue #{issue_number}",
        url: "https://example.test/issues/#{issue_number}",
        developer_id: "developer-a",
        priority: "Priority: High",
        effort_hours: 4,
        starts_on: Date.new(2026, 8, 31),
        position: position
      )
    end
  end
end
