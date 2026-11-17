require "cgi"
require "date"
require "json"
require "net/http"
require "timeout"
require "uri"

module GithubIssueOrganizerEngine
  module Github
    class Client
      API_ROOT = "https://api.github.com"
      API_VERSION = "2022-11-28"
      PER_PAGE = 100
      MAX_RESULTS_PER_REPOSITORY = 1_000

      class Error < StandardError; end
      class AuthenticationError < Error; end
      class RateLimitError < Error; end
      class RepositoryAccessError < Error; end

      Result = Struct.new(:issues, :incomplete_results, keyword_init: true)

      def initialize(token:, repositories: GithubIssueOrganizerEngine.configuration.repositories)
        @token = token.to_s.strip
        @repositories = repositories
        raise AuthenticationError, "GitHub access is not configured" if @token.empty?
      end

      def search(query)
        issues = []
        incomplete_results = false

        @repositories.each do |repository|
          repository_result = search_repository(query.repository_query(repository), repository)
          issues.concat(repository_result.issues)
          incomplete_results ||= repository_result.incomplete_results
        end

        Result.new(issues: issues, incomplete_results: incomplete_results)
      end

      def user(login)
        unless login.match?(/\A[a-z\d](?:[a-z\d-]{0,37}[a-z\d])?\z/i)
          raise ArgumentError, "Invalid GitHub username"
        end

        request_json("/users/#{CGI.escape(login)}")
      end

      def open_issues
        raise ArgumentError, "Configure at least one repository in Settings" if @repositories.empty?

        @repositories.flat_map do |repository|
          issues = []
          page = 1
          loop do
            items = request_json("/repos/#{repository}/issues",
              state: "open", sort: "created", direction: "asc", per_page: PER_PAGE, page: page)
            raise Error, "GitHub returned an invalid issue list" unless items.is_a?(Array)

            issues.concat(items.reject { |item| item.key?("pull_request") })
            break if items.size < PER_PAGE

            page += 1
          end
          issues
        end.uniq { |issue| issue.fetch("id") }
      end

      def milestone_issues(repository:, milestone_number:)
        raise ArgumentError, "Unknown milestone repository" unless @repositories.include?(repository)

        issues = []
        page = 1
        loop do
          items = request_json("/repos/#{repository}/issues",
            milestone: milestone_number, state: "all", sort: "created", direction: "asc", per_page: PER_PAGE, page: page)
          raise Error, "GitHub returned an invalid issue list" unless items.is_a?(Array)

          issues.concat(items.reject { |item| item.key?("pull_request") }.map do |item|
            {
              "number" => item.fetch("number"),
              "title" => item.fetch("title", "Issue ##{item.fetch('number')}"),
              "state" => item.fetch("state"),
              "closed_on" => item["closed_at"] && Date.iso8601(item["closed_at"]).iso8601
            }
          end)
          break if items.size < PER_PAGE

          page += 1
        end
        issues.uniq { |issue| issue.fetch("number") }
      end

      def milestones
        raise ArgumentError, "Configure at least one repository in Settings" if @repositories.empty?

        @repositories.flat_map do |repository|
          milestones = []
          page = 1
          loop do
            items = request_json("/repos/#{repository}/milestones",
              state: "all", sort: "due_on", direction: "asc", per_page: PER_PAGE, page: page)
            raise Error, "GitHub returned an invalid milestone list" unless items.is_a?(Array)

            milestones.concat(items.map do |item|
              {
                "id" => item.fetch("id").to_s,
                "repository" => repository,
                "number" => item.fetch("number"),
                "title" => item.fetch("title"),
                "state" => item.fetch("state"),
                "due_on" => item["due_on"] && Date.iso8601(item["due_on"]).iso8601,
                "url" => "https://github.com/#{repository}/milestone/#{item.fetch('number')}"
              }
            end)
            break if items.size < PER_PAGE

            page += 1
          end
          milestones
        end
      end

      private

      def search_repository(query, repository)
        issues = []
        incomplete_results = false
        page = 1
        retrieved = 0
        total = 0

        loop do
          payload = request_json(
            "/search/issues",
            q: query,
            per_page: PER_PAGE,
            page: page
          )
          items = Array(payload["items"])
          total = [ payload.fetch("total_count", 0), MAX_RESULTS_PER_REPOSITORY ].min
          retrieved += items.length
          issues.concat(items.reject { |item| item.key?("pull_request") })
          incomplete_results ||= payload["incomplete_results"]
          incomplete_results ||= payload.fetch("total_count", 0) > MAX_RESULTS_PER_REPOSITORY
          break if retrieved >= total || items.empty? || page >= 10

          page += 1
        end

        Result.new(issues: issues, incomplete_results: incomplete_results)
      rescue RepositoryAccessError => error
        raise RepositoryAccessError, "Cannot access #{repository}: #{error.message}"
      end

      def request_json(path, query = {})
        uri = URI.join(API_ROOT, path)
        uri.query = URI.encode_www_form(query) if query.any?

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github+json"
        request["Authorization"] = "Bearer #{@token}"
        request["User-Agent"] = "github-issue-organizer-engine/#{GithubIssueOrganizerEngine::VERSION}"
        request["X-GitHub-Api-Version"] = API_VERSION

        response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 20
        ) { |http| http.request(request) }

        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        when Net::HTTPUnauthorized
          raise AuthenticationError, "GitHub rejected the configured token"
        when Net::HTTPForbidden
          raise RateLimitError, "GitHub denied the request or the API rate limit was reached"
        when Net::HTTPNotFound, Net::HTTPUnprocessableEntity
          raise RepositoryAccessError,
            "the repository is unavailable to the configured credentials. " \
            "Check its owner/repository name in Settings and the host application's GitHub token. " \
            "For private repositories moved to an organization, a fine-grained token must use " \
            "that organization as its resource owner, include the repositories, and have Issues read access " \
            "with any required organization approval. Your browser's GitHub access does not grant the server token access."
        else
          raise Error, "GitHub API request failed with HTTP #{response.code}"
        end
      rescue JSON::ParserError
        raise Error, "GitHub returned an invalid response"
      rescue SocketError, SystemCallError, Timeout::Error => error
        raise Error, "GitHub request failed: #{error.message}"
      end
    end
  end
end
