module GithubIssueOrganizerEngine
  class TimelineItemsController < ApplicationController
    before_action :set_timeline

    def update
      item = @timeline.items.find(params[:id])
      TimelineItemMover.new(
        timeline: @timeline,
        item: item,
        developer_id: item_params.fetch(:developer_id),
        before_item_id: item_params[:before_item_id]
      ).call

      render json: {
        message: "Issue moved and schedule shifted.",
        timeline_url: edit_timeline_path(@timeline)
      }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def set_timeline
      @timeline = Timeline.includes(:items, :unavailabilities).find(params[:timeline_id])
    end

    def item_params
      params.require(:timeline_item).permit(:developer_id, :before_item_id)
    end
  end
end
