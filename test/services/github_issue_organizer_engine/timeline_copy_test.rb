require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_copy"

module GithubIssueOrganizerEngine
  class TimelineCopyTest < Minitest::Test
    FakeChild = Struct.new(:attributes, keyword_init: true)

    class FakeAssociation < Array
      attr_reader :created_attributes

      def initialize(children = [])
        super(children)
        @created_attributes = []
      end

      def create!(attributes)
        @created_attributes << attributes
      end
    end

    FakeTimeline = Struct.new(
      :id, :created_by_id, :attributes, :items, :unavailabilities,
      keyword_init: true
    )
    FakeCopy = Struct.new(:items, :unavailabilities, keyword_init: true)

    class FakeTimelineClass
      class << self
        attr_reader :created_attributes

        def transaction
          yield
        end

        def statuses
          { draft: "draft" }
        end

        def create!(attributes)
          @created_attributes = attributes
          FakeCopy.new(items: FakeAssociation.new, unavailabilities: FakeAssociation.new)
        end
      end
    end

    def test_copies_timeline_children_and_records_origin_and_editor
      source = FakeTimeline.new(
        id: 12,
        created_by_id: 4,
        attributes: {
          "starts_on" => Date.new(2026, 9, 4),
          "query" => { "state" => "open" },
          "developer_count" => 1,
          "developer_ids" => [ "developer-a" ],
          "in_review_issues" => [],
          "blocked_issues" => [],
          "needs_effort_issues" => [ { "title" => "Needs sizing" } ],
          "status" => "current"
        },
        items: FakeAssociation.new([
          FakeChild.new(attributes: { "id" => 2, "timeline_id" => 12, "position" => 1, "title" => "Issue", "created_at" => Time.now })
        ]),
        unavailabilities: FakeAssociation.new([
          FakeChild.new(attributes: { "id" => 3, "timeline_id" => 12, "developer_id" => "developer-a", "reason" => "Holiday" })
        ])
      )

      copy = TimelineCopy.new(timeline: source, editor_id: 9, timeline_class: FakeTimelineClass).call

      assert_equal 4, FakeTimelineClass.created_attributes.fetch("created_by_id")
      assert_equal 9, FakeTimelineClass.created_attributes.fetch("edited_by_id")
      assert_equal 12, FakeTimelineClass.created_attributes.fetch("source_timeline_id")
      assert_equal "draft", FakeTimelineClass.created_attributes.fetch("status")
      assert_equal [ { "title" => "Needs sizing" } ], FakeTimelineClass.created_attributes.fetch("needs_effort_issues")
      assert_equal({ "position" => 1, "title" => "Issue" }, copy.items.created_attributes.sole)
      assert_equal({ "developer_id" => "developer-a", "reason" => "Holiday" }, copy.unavailabilities.created_attributes.sole)
    end

    def test_requires_an_editor
      source = FakeTimeline.new

      assert_raises(ArgumentError) do
        TimelineCopy.new(timeline: source, editor_id: nil, timeline_class: FakeTimelineClass).call
      end
    end
  end
end
