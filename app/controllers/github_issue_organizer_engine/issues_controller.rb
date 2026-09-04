module GithubIssueOrganizerEngine
  class IssuesController < ApplicationController
    class MissingGithubIdentityError < ArgumentError; end

    rescue_from ArgumentError, with: :render_bad_request
    rescue_from Github::Client::Error, with: :render_github_error

    def index
      @suggested_labels = suggested_labels
      @github_identity = current_github_identity
      @repositories = configured_repositories
    end

    def github_url
      render json: { url: search_query.github_url }
    end

    def open_in_github
      redirect_to search_query.github_url, allow_other_host: true
    rescue MissingGithubIdentityError => error
      redirect_to github_identity_path, alert: error.message
    end

    def timeline
      starts_on = params.require(:starts_on)
      query = search_query
      unless query.filters["result_type"] == "issues"
        raise ArgumentError, "Timelines can only be drafted from issues"
      end
      developer_ids = configured_developer_ids
      unless developer_ids.size.between?(1, 100)
        raise ArgumentError, "Configure between 1 and 100 developer IDs in Settings"
      end
      unavailability = inherited_unavailability(developer_ids)

      github_result = github_client.search(query)
      inherited_assignments = inherited_manual_assignments(github_result.issues, developer_ids)
      scheduler = Scheduler.new(
        issues: inherited_assignments.issues,
        starts_on: starts_on,
        developer_ids: developer_ids,
        unavailability: unavailability,
        ordered_issue_ids: ordered_issue_ids
      )
      ranking_groups = scheduler.tie_groups
      unless ranking_groups.empty? || tie_breaker_selected?
        render json: {
          ranking_required: true,
          ranking_groups: ranking_groups,
          incomplete_results: github_result.incomplete_results
        }
        return
      end
      validate_manual_order!(ranking_groups)

      result = scheduler.call
      if github_result.incomplete_results
        raise ArgumentError, "GitHub reported incomplete results; this draft was not saved"
      end
      timeline = persist_timeline(result, query, unavailability)

      render json: {
        scheduled: result.scheduled,
        in_review: result.in_review,
        blocked: result.blocked,
        needs_labels: result.needs_labels,
        total_hours: result.total_hours,
        developer_count: result.developer_count,
        developer_ids: result.developer_ids,
        starts_on: starts_on,
        ends_on: result.ends_on,
        incomplete_results: github_result.incomplete_results,
        inherited_unavailability_count: unavailability.size,
        inherited_manual_assignment_count: inherited_assignments.count,
        timeline_id: timeline.id,
        timeline_url: timeline_path(timeline),
        github_url: query.github_url
      }
    end

    private

    def search_query
      filters = search_params.to_h
      filters["labels"] = Array(filters["labels"])
      custom_label = params[:custom_label].to_s.strip
      filters["labels"] << custom_label if custom_label.present?

      %w[assignee creator].each do |field|
        filters[field] = linked_github_login if filters[field].to_s.strip.casecmp?("@me")
      end

      SearchQuery.new(filters, repositories: configured_repositories)
    end

    def search_params
      params.slice(
        :state,
        :result_type,
        :label_match,
        :assignee,
        :creator,
        :title,
        :sort,
        :no_priority,
        :labels
      ).permit(
        :state,
        :result_type,
        :label_match,
        :assignee,
        :creator,
        :title,
        :sort,
        :no_priority,
        labels: []
      )
    end

    def tie_breaker_selected?
      %w[manual created_at].include?(params[:tie_breaker])
    end

    def ordered_issue_ids
      return [] unless params[:tie_breaker] == "manual"

      Array(params[:issue_order]).map(&:to_s)
    end

    def validate_manual_order!(ranking_groups)
      return unless params[:tie_breaker] == "manual"

      expected_ids = ranking_groups.flat_map { |group| group.fetch("issues") }
        .map { |issue| issue.fetch("id") }
      submitted_ids = ordered_issue_ids
      return if submitted_ids == submitted_ids.uniq && submitted_ids.sort == expected_ids.sort

      raise ArgumentError, "Choose a schedule position for every tied issue"
    end

    def linked_github_login
      current_github_identity&.github_login ||
        raise(MissingGithubIdentityError, "Link your GitHub username before using @me")
    end

    def persist_timeline(result, query, unavailability)
      raise ArgumentError, "No schedulable issues found. Check your filters and try again." if result.scheduled.empty?

      user_id = current_host_user_id || raise(ArgumentError, "No host user is available")

      Timeline.transaction do
        timeline = Timeline.create!(
          created_by_id: user_id,
          starts_on: params[:starts_on],
          developer_count: result.developer_count,
          developer_ids: result.developer_ids,
          query: query.filters,
          in_review_issues: result.in_review,
          blocked_issues: result.blocked,
          needs_effort_issues: result.needs_labels.select do |issue|
            issue["missing"] == [ "effort" ]
          end
        )

        timeline.items.create!(result.scheduled.map { |item| timeline_item_attributes(item) })

        unavailability.each do |period|
          timeline.unavailabilities.create!(
            developer_id: period.fetch(:developer_id),
            starts_at: period.fetch(:starts_at),
            ends_at: period.fetch(:ends_at)
          )
        end

        timeline
      end
    end

    def timeline_item_attributes(item)
      item.slice(*TimelineItem.attribute_names)
    end

    def inherited_unavailability(developer_ids)
      inherit_periods = ActiveModel::Type::Boolean.new.cast(
        params.fetch(:inherit_unavailability, "1")
      )
      return [] unless inherit_periods

      return [] unless previous_timeline

      previous_timeline.unavailabilities.filter_map do |period|
        next unless developer_ids.include?(period.developer_id)

        {
          developer_id: period.developer_id,
          starts_at: period.starts_at,
          ends_at: period.ends_at
        }
      end
    end

    def inherited_manual_assignments(issues, developer_ids)
      inherit_assignments = ActiveModel::Type::Boolean.new.cast(
        params.fetch(:inherit_manual_assignments, "1")
      )
      return TimelineAssignmentInheritor::Result.new(issues: issues, count: 0) unless inherit_assignments

      TimelineAssignmentInheritor.new(
        issues: issues,
        timeline: previous_timeline,
        developer_ids: developer_ids
      ).call
    end

    def previous_timeline
      @previous_timeline ||= Timeline.includes(:items, :unavailabilities).order(created_at: :desc).first
    end

    def suggested_labels
      [
        *Scheduler::PRIORITY_RANKS.keys,
        "Announcements",
        *Scheduler::EFFORT_HOURS.keys,
        "Status: Backlog",
        "Status: Blocked",
        "Status: In-progress",
        "Status: Review",
        "Team: Client",
        "Team: Legal",
        "Team: Marketing",
        "Team: Product",
        "WorkType: Bug",
        "WorkType: Design",
        "WorkType: Documentation",
        "WorkType: Enhancement",
        "WorkType: Feature",
        "WorkType: Research"
      ]
    end

    def render_bad_request(error)
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def render_github_error(error)
      render json: { error: error.message }, status: :bad_gateway
    end
  end
end
