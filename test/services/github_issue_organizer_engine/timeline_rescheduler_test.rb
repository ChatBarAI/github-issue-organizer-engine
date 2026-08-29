require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_rescheduler"

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

    private

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
        position: position
      )
    end
  end
end
