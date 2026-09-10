require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_rescheduler"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_item_mover"

module GithubIssueOrganizerEngine
  class TimelineItemMoverTest < Minitest::Test
    FakeItem = Struct.new(
      :id,
      :developer_id,
      :starts_on,
      :position,
      :work_segments,
      :manually_assigned,
      :effort_hours,
      :ends_on,
      :developer_position,
      keyword_init: true
    ) do
      def update!(attributes)
        attributes.each { |name, value| public_send("#{name}=", value) }
      end
    end

    FakeTimeline = Struct.new(:developer_ids, :items, :starts_on, :unavailabilities, keyword_init: true) do
      def transaction
        yield
      end
    end

    def test_moves_an_issue_to_an_explicit_position_without_allowing_reassignment
      first = fake_item(1, "developer-a", 1)
      second = fake_item(2, "developer-a", 2)
      third = fake_item(3, "developer-b", 3)
      timeline = FakeTimeline.new(
        developer_ids: [ "developer-a", "developer-b" ],
        items: [ first, second, third ]
      )
      rescheduler = Object.new.tap { |object| object.define_singleton_method(:call) { timeline } }
      rescheduler_arguments = nil

      TimelineRescheduler.stub(:new, ->(**arguments) { rescheduler_arguments = arguments; rescheduler }) do
        TimelineItemMover.new(
          timeline: timeline,
          item: first,
          developer_id: "developer-b",
          before_item_id: third.id
        ).call
      end

      assert_equal "developer-b", first.developer_id
      assert_equal true, first.manually_assigned
      assert_equal false, rescheduler_arguments.fetch(:allow_reassignment)
      assert_equal [ 2, 1, 3 ], rescheduler_arguments.fetch(:ordered_item_ids)
    end

    def test_rejects_a_developer_outside_the_timeline
      timeline = FakeTimeline.new(
        developer_ids: [ "developer-a" ],
        items: [ fake_item(1, "developer-a", 1) ]
      )

      error = assert_raises(ArgumentError) do
        TimelineItemMover.new(
          timeline: timeline,
          item: timeline.items.first,
          developer_id: "developer-b"
        ).call
      end

      assert_equal "Unknown timeline developer", error.message
    end

    def test_dropping_an_issue_back_in_its_original_position_is_a_no_op
      first = fake_item(1, "developer-a", 1)
      second = fake_item(2, "developer-a", 2)
      timeline = FakeTimeline.new(
        developer_ids: [ "developer-a" ],
        items: [ first, second ]
      )

      TimelineRescheduler.stub(:new, ->(**) { flunk "a no-op move should not reschedule the timeline" }) do
        result = TimelineItemMover.new(
          timeline: timeline,
          item: first,
          developer_id: "developer-a",
          before_item_id: second.id
        ).call

        assert_same timeline, result
      end

      assert_equal "developer-a", first.developer_id
      assert_equal false, first.manually_assigned
    end

    def test_moves_into_vacant_past_hours_without_rescheduling_other_issues
      moving = fake_item(1, "developer-a", 1)
      moving.effort_hours = 8
      other = fake_item(2, "developer-a", 2)
      other.starts_on = Date.new(2026, 9, 10)
      other.ends_on = other.starts_on
      timeline = FakeTimeline.new(developer_ids: ["developer-a"], items: [moving, other],
        starts_on: Date.new(2026, 9, 10), unavailabilities: [])

      TimelineRescheduler.stub(:new, ->(**) { flunk "past moves must not reschedule other work" }) do
        TimelineItemMover.new(timeline: timeline, item: moving, developer_id: "developer-a",
          starts_at: "2026-09-04T13:00:00+00:00").call
      end
      assert_equal Date.new(2026, 9, 4), moving.starts_on
      assert_equal Date.new(2026, 9, 7), moving.ends_on
      assert_equal "2026-09-07T13:00:00+00:00", moving.work_segments.last.fetch("ends_at")
      assert_equal Date.new(2026, 9, 10), other.starts_on
      assert moving.manually_assigned
    end

    def test_rejects_overlap_including_carried_history_and_unavailability
      moving = fake_item(1, "developer-a", 1)
      moving.effort_hours = 8
      occupied = fake_item(2, "developer-a", 2)
      occupied.starts_on = Date.new(2026, 9, 7)
      occupied.work_segments = [{"starts_at" => "2026-09-10T09:00:00+00:00", "ends_at" => "2026-09-10T17:00:00+00:00"}]
      period = Struct.new(:developer_id, :starts_at, :ends_at).new("developer-a",
        DateTime.iso8601("2026-09-07T13:00:00+00:00"), DateTime.iso8601("2026-09-07T14:00:00+00:00"))
      [[occupied], []].each do |other_items|
        timeline = FakeTimeline.new(developer_ids: ["developer-a"], items: [moving, *other_items],
          starts_on: Date.new(2026, 9, 10), unavailabilities: other_items.empty? ? [period] : [])
        original_date = moving.starts_on
        assert_raises(ArgumentError) do
          TimelineItemMover.new(timeline: timeline, item: moving, developer_id: "developer-a",
            starts_at: "2026-09-07T09:00:00+00:00").call
        end
        assert_equal original_date, moving.starts_on
      end
    end

    private

    def fake_item(id, developer_id, position)
      FakeItem.new(
        id: id,
        developer_id: developer_id,
        starts_on: Date.new(2026, 8, 28) + position,
        position: position,
        work_segments: [],
        manually_assigned: false
      )
    end
  end
end
