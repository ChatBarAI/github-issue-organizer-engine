require "set"

module GithubIssueOrganizerEngine
  class TimelineRevisionList
    Row = Data.define(:timeline, :depth)
    STATUS_PRIORITY = { "current" => 0, "draft" => 1, "obsolete" => 2 }.freeze

    def initialize(timelines)
      @timelines = timelines.to_a
      @by_id = @timelines.index_by(&:id)
    end

    def call
      displayed_ids = Set.new
      rows = []

      leaves.sort_by { |timeline| family_sort_key(timeline) }.each do |timeline|
        append_chain(timeline, rows, displayed_ids)
      end
      @timelines.sort_by { |timeline| timeline_sort_key(timeline) }.each do |timeline|
        append_chain(timeline, rows, displayed_ids) unless displayed_ids.include?(timeline.id)
      end

      rows
    end

    private

    def leaves
      parent_ids = @timelines.filter_map(&:source_timeline_id).to_set
      @timelines.reject { |timeline| parent_ids.include?(timeline.id) }
    end

    def append_chain(timeline, rows, displayed_ids)
      depth = 0
      while timeline && displayed_ids.add?(timeline.id)
        rows << Row.new(timeline:, depth:)
        timeline = @by_id[timeline.source_timeline_id]
        depth += 1
      end
    end

    def family_sort_key(timeline)
      chain = []
      member = timeline
      seen_ids = Set.new
      while member && seen_ids.add?(member.id)
        chain << member
        member = @by_id[member.source_timeline_id]
      end

      [ chain.map { |entry| STATUS_PRIORITY.fetch(entry.status, 3) }.min, -timeline.created_at.to_f ]
    end

    def timeline_sort_key(timeline)
      [ STATUS_PRIORITY.fetch(timeline.status, 3), -timeline.created_at.to_f ]
    end
  end
end
