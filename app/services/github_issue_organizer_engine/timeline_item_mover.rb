module GithubIssueOrganizerEngine
  class TimelineItemMover
    def initialize(timeline:, item:, developer_id:, before_item_id: nil)
      @timeline = timeline
      @item = item
      @developer_id = developer_id.to_s
      @before_item_id = before_item_id.presence
    end

    def call
      raise ArgumentError, "Unknown timeline developer" unless @timeline.developer_ids.include?(@developer_id)

      @timeline.transaction do
        queues = @timeline.developer_ids.to_h do |developer_id|
          [ developer_id, scheduled_items.select { |item| item.developer_id == developer_id } ]
        end
        original_ordered_item_ids = ordered_item_ids(queues)
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
        return @timeline if @item.developer_id == @developer_id &&
          ordered_item_ids(queues) == original_ordered_item_ids

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
