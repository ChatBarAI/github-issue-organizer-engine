require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/timeline_revision_list"

module GithubIssueOrganizerEngine
  class TimelineRevisionListTest < Minitest::Test
    TimelineRecord = Data.define(:id, :source_timeline_id, :status, :created_at)

    def test_places_the_latest_revision_before_its_indented_ancestors
      original = timeline(1, nil, "obsolete", 1)
      first_edit = timeline(2, 1, "obsolete", 2)
      latest_edit = timeline(3, 2, "current", 3)

      rows = TimelineRevisionList.new([ original, latest_edit, first_edit ]).call

      assert_equal [ 3, 2, 1 ], rows.map { |row| row.timeline.id }
      assert_equal [ 0, 1, 2 ], rows.map(&:depth)
    end

    def test_prioritizes_the_family_containing_the_current_timeline
      unrelated_draft = timeline(4, nil, "draft", 4)
      old_current = timeline(1, nil, "obsolete", 1)
      current = timeline(2, 1, "current", 2)

      rows = TimelineRevisionList.new([ unrelated_draft, old_current, current ]).call

      assert_equal [ 2, 1, 4 ], rows.map { |row| row.timeline.id }
    end

    private

    def timeline(id, source_timeline_id, status, created_at)
      TimelineRecord.new(id:, source_timeline_id:, status:, created_at: Time.at(created_at))
    end
  end
end
