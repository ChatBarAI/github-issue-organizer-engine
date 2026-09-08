require_relative "../../test_helper"
require_relative "../../../app/services/github_issue_organizer_engine/github/client"

module GithubIssueOrganizerEngine
  class GithubClientTest < Minitest::Test
    def test_open_issues_reads_beyond_search_limit_and_excludes_pull_requests
      client = Github::Client.new(token: "test", repositories: ["example/one", "example/two"])
      calls = []
      client.define_singleton_method(:request_json) do |path, query|
        calls << [path, query]
        if path == "/repos/example/two/issues"
          [{ "id" => 1 }, { "id" => 2000 }]
        elsif query[:page] <= 11
          Array.new(100) { |i| { "id" => (query[:page] - 1) * 100 + i + 1 } }
        else
          [{ "id" => 1200, "pull_request" => {} }]
        end
      end

      assert_equal 1101, client.open_issues.size
      assert_equal 13, calls.size
      assert calls.all? { |_, query| query[:state] == "open" && query[:per_page] == 100 }
    end

    def test_later_page_failure_does_not_return_partial_results
      client = Github::Client.new(token: "test", repositories: ["example/one"])
      client.define_singleton_method(:request_json) do |_, query|
        raise Github::Client::RateLimitError, "Rate limit reached" if query[:page] == 2

        Array.new(100) { |i| { "id" => i } }
      end

      assert_raises(Github::Client::RateLimitError) { client.open_issues }
    end

    def test_requires_repositories
      client = Github::Client.new(token: "test", repositories: [])
      assert_raises(ArgumentError) { client.open_issues }
    end
  end
end
