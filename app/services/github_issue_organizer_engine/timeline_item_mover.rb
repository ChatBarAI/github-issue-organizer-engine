module GithubIssueOrganizerEngine
  class TimelineItemMover
    def initialize(timeline:, item:, developer_id:, before_item_id: nil, starts_at: nil)
      @timeline = timeline
      @item = item
      @developer_id = developer_id.to_s
      @before_item_id = before_item_id.presence
      @starts_at = starts_at.presence
    end

    def call
      raise ArgumentError, "Unknown timeline developer" unless @timeline.developer_ids.include?(@developer_id)

      return move_to_slot if @starts_at

      @timeline.transaction do
        queues = @timeline.developer_ids.to_h do |developer_id|
          [ developer_id, scheduled_items.select { |item| item.developer_id == developer_id } ]
        end
        queues.each_value { |items| items.delete(@item) }

        destination = queues.fetch(@developer_id)
        insertion_index = destination.length
        if @before_item_id
          before_item = @timeline.items.find { |item| item.id.to_s == @before_item_id.to_s }
          unless before_item && before_item != @item && before_item.developer_id == @developer_id
            raise ArgumentError, "Invalid issue insertion point"
          end
          insertion_index = destination.index(before_item) || destination.length
        end

        destination.insert(insertion_index, @item)

        @item.update!(developer_id: @developer_id, manually_assigned: true)

        TimelineRescheduler.new(
          timeline: @timeline,
          allow_reassignment: false,
          ordered_item_ids: ordered_item_ids(queues)
        ).call
      end

      @timeline
    end

    private

    def move_to_slot
      start = DateTime.iso8601(@starts_at)
      unless (9...17).cover?(start.hour) &&
          start.min.zero? && start.sec.zero? && !start.saturday? && !start.sunday?
        raise ArgumentError, "Choose a weekday work slot between 09:00 and 17:00"
      end

      segments = []
      cursor = start
      remaining = @item.effort_hours
      while remaining.positive?
        hours = [remaining, 17 - cursor.hour].min
        finish = cursor + Rational(hours, 24)
        segments << { "starts_at" => cursor.iso8601, "ends_at" => finish.iso8601 }
        remaining -= hours
        date = cursor.to_date + 1
        date += 1 while date.saturday? || date.sunday?
        cursor = DateTime.new(date.year, date.month, date.day, 9)
      end

      @timeline.transaction do
        occupied = @timeline.items.reject { |item| item == @item || item.developer_id != @developer_id }.flat_map do |item|
          periods = Array(item.work_segments).map { |segment| [DateTime.iso8601(segment.fetch("starts_at")), DateTime.iso8601(segment.fetch("ends_at"))] }
          if periods.empty?
            periods << [item.starts_on.to_datetime + Rational(9, 24),
              item.ends_on.to_datetime + Rational(17, 24)]
          end
          periods
        end
        occupied += @timeline.unavailabilities.select { |period| period.developer_id == @developer_id }
          .map { |period| [period.starts_at.to_datetime, period.ends_at.to_datetime] }
        overlap = segments.any? do |segment|
          from = DateTime.iso8601(segment.fetch("starts_at"))
          to = DateTime.iso8601(segment.fetch("ends_at"))
          occupied.any? { |occupied_from, occupied_to| from < occupied_to && to > occupied_from }
        end
        raise ArgumentError, "The issue does not fit in vacant time at that position" if overlap

        @item.update!(developer_id: @developer_id,
          developer_position: @timeline.developer_ids.index(@developer_id) + 1,
          manually_assigned: true, starts_on: start.to_date,
          ends_on: DateTime.iso8601(segments.last.fetch("ends_at")).to_date,
          work_segments: segments)
      end
      @timeline
    end

    def ordered_item_ids(queues)
      @timeline.developer_ids.flat_map { |developer_id| queues.fetch(developer_id).map(&:id) }
    end

    def scheduled_items
      @scheduled_items ||= @timeline.items.sort_by do |item|
        first_segment_start = Array(item.work_segments).first&.fetch("starts_at", nil)
        [ item.starts_on, first_segment_start.to_s, item.position ]
      end
    end
  end
end
