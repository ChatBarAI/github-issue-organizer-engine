module GithubIssueOrganizerEngine
  class MilestoneForecast
    Result = Data.define(:status, :label, :detail)
    IssueDetail = Data.define(:repository, :number, :title, :state, :ends_on, :closed_on, :forecast)

    def initialize(items:, today: Date.current)
      @items = items.index_by { |item| [item.repository.downcase, item.issue_number.to_i] }
      @today = today
    end

    def call(milestones)
      late = []
      uncertain = []
      open_count = 0
      issue_count = 0
      milestones.each do |milestone|
        unless milestone.key?("issues")
          uncertain << "#{milestone.fetch('repository')}: issue status has not been checked"
          next
        end

        due_on = Date.iso8601(milestone.fetch("due_on"))
        milestone.fetch("issues").each do |issue|
          issue_count += 1
          reference = "#{milestone.fetch('repository')}##{issue.fetch('number')}"
          if issue.fetch("state") == "closed"
            if issue["closed_on"].blank?
              uncertain << "#{reference}: completion date is unknown"
            elsif Date.iso8601(issue.fetch("closed_on")) > due_on
              late << "#{reference}: completed after the due date"
            end
          elsif issue.fetch("state") == "open"
            open_count += 1
            item = @items[[milestone.fetch("repository").downcase, issue.fetch("number").to_i]]
            if due_on < @today
              late << "#{reference}: still open after the due date"
            elsif item&.ends_on && item.ends_on > due_on
              late << "#{reference}: scheduled to finish #{item.ends_on.iso8601}"
            elsif !item&.ends_on
              uncertain << "#{reference}: no scheduled finish date"
            elsif item.ends_on < @today
              uncertain << "#{reference}: still open after its scheduled finish"
            end
          else
            uncertain << "#{reference}: issue state is unknown"
          end
        end
      end

      if late.any?
        Result.new(status: :late, label: "Late", detail: summarize(late + uncertain))
      elsif uncertain.any?
        Result.new(status: :uncertain, label: "Uncertain", detail: summarize(uncertain))
      elsif issue_count.zero?
        Result.new(status: :uncertain, label: "Uncertain", detail: "No issues are linked to this milestone")
      elsif open_count.zero?
        Result.new(status: :on_track, label: "Completed on time", detail: "All #{issue_count} issues were closed by the due date")
      else
        Result.new(status: :on_track, label: "On track", detail: "All #{issue_count} issues are completed or scheduled to finish by the due date")
      end
    end

    def issue_details(milestones)
      milestones.flat_map do |milestone|
        Array(milestone["issues"]).map do |issue|
          item = @items[[milestone.fetch("repository").downcase, issue.fetch("number").to_i]]
          IssueDetail.new(
            repository: milestone.fetch("repository"), number: issue.fetch("number"),
            title: issue["title"].presence || item.try(:title).presence || "Issue ##{issue.fetch('number')}",
            state: issue.fetch("state"), ends_on: item&.ends_on,
            closed_on: issue["closed_on"].presence && Date.iso8601(issue.fetch("closed_on")),
            forecast: call([milestone.merge("issues" => [issue])])
          )
        end
      end.sort_by { |issue| [{ late: 0, uncertain: 1, on_track: 2 }.fetch(issue.forecast.status), issue.repository, issue.number.to_i] }
    end

    private

    def summarize(reasons)
      summary = reasons.first(4).join("; ")
      reasons.size > 4 ? "#{summary}; and #{reasons.size - 4} more" : summary
    end
  end
end
