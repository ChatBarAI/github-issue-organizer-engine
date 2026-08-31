require "cgi"

module GithubIssueOrganizerEngine
  class SearchQuery
    VALID_STATES = %w[open closed all].freeze
    VALID_RESULT_TYPES = %w[issues review_requested pull_requests].freeze
    VALID_MATCH_MODES = %w[single all any].freeze
    VALID_SORTS = %w[
      updated-desc
      updated-asc
      created-desc
      created-asc
      comments-desc
      reactions-desc
    ].freeze

    attr_reader :filters

    def initialize(params, repositories: GithubIssueOrganizerEngine.configuration.repositories)
      @repositories = repositories
      @filters = normalize(params)
    end

    def web_query
      build(repository_expression)
    end

    def repository_query(repository)
      raise ArgumentError, "Unknown repository" unless @repositories.include?(repository)

      build("repo:#{repository}", include_sort: false)
    end

    def github_url
      "https://github.com/issues?q=#{CGI.escape(web_query).gsub("+", "%20")}"
    end

    private

    def normalize(params)
      raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      state = raw.fetch("state", "open").to_s
      result_type = raw.fetch("result_type", "issues").to_s
      match_mode = raw.fetch("label_match", "single").to_s
      sort = raw.fetch("sort", "updated-desc").to_s

      filters = {
        "state" => VALID_STATES.include?(state) ? state : "open",
        "result_type" => VALID_RESULT_TYPES.include?(result_type) ? result_type : "issues",
        "label_match" => VALID_MATCH_MODES.include?(match_mode) ? match_mode : "single",
        "sort" => VALID_SORTS.include?(sort) ? sort : "updated-desc",
        "labels" => Array(raw["labels"])
          .first(50)
          .map { |label| label.to_s.strip.first(100) }
          .reject(&:blank?)
          .uniq,
        "assignee" => normalize_login(raw["assignee"], allow_unassigned: true),
        "creator" => normalize_login(raw["creator"]),
        "title" => raw["title"].to_s.strip.first(200),
        "no_priority" => [ true, 1, "1", "true", "on" ].include?(raw["no_priority"])
      }

      if filters["no_priority"]
        filters["labels"] -= Scheduler::PRIORITY_RANKS.keys
      end

      filters
    end

    def normalize_login(value, allow_unassigned: false)
      login = value.to_s.delete_prefix("@").strip
      return "unassigned" if allow_unassigned && login.casecmp?("unassigned")
      return "" if login.blank?

      unless login.match?(/\A[a-z\d](?:[a-z\d-]{0,37}[a-z\d])?\z/i)
        raise ArgumentError, "Invalid GitHub username"
      end

      login
    end

    def build(repository, include_sort: true)
      parts = [ result_type_qualifier ]
      parts << "state:#{filters["state"]}" unless filters["state"] == "all"

      if filters["assignee"] == "unassigned"
        parts << "no:assignee"
      elsif filters["assignee"].present?
        parts << "assignee:#{filters["assignee"]}"
      end

      parts << "author:#{filters["creator"]}" if filters["creator"].present?
      parts << %("#{escape(filters["title"])}" in:title) if filters["title"].present?
      parts << repository
      parts.concat(label_qualifiers)
      parts.concat(no_priority_qualifiers) if filters["no_priority"]
      parts << "sort:#{filters["sort"]}" if include_sort
      parts.join(" ")
    end

    def repository_expression
      @repositories.map { |repository| "repo:#{repository}" }.join(" OR ").then { |value| "(#{value})" }
    end

    def result_type_qualifier
      case filters["result_type"]
      when "review_requested"
        "is:pr user-review-requested:@me"
      when "pull_requests"
        "is:pr"
      else
        "is:issue"
      end
    end

    def label_qualifiers
      labels = filters["labels"].map { |label| %Q("#{escape(label)}") }
      return [] if labels.empty?

      if filters["label_match"] == "any"
        [ "label:#{labels.join(",")}" ]
      else
        labels.map { |label| "label:#{label}" }
      end
    end

    def no_priority_qualifiers
      Scheduler::PRIORITY_RANKS.keys.map { |label| %Q(-label:"#{escape(label)}") }
    end

    def escape(value)
      value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')
    end
  end
end
