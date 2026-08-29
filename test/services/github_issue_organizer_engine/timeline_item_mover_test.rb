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
      keyword_init: true
    ) do
      def update!(attributes)
        attributes.each { |name, value| public_send("#{name}=", value) }
      end
    end

    FakeTimeline = Struct.new(:developer_ids, :items, keyword_init: true) do
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
