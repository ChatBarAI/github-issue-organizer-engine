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

    def test_milestones_paginates_each_repository_and_keeps_calendar_due_date
      client = Github::Client.new(token: "test", repositories: ["example/one", "example/two"])
      calls = []
      client.define_singleton_method(:request_json) do |path, query|
        calls << [path, query]
        count = path == "/repos/example/one/milestones" && query[:page] == 1 ? 100 : 1
        Array.new(count) do |i|
          { "id" => query[:page] * 100 + i, "number" => i + 1, "title" => "Release",
            "state" => "closed", "due_on" => query[:page] == 1 ? "2026-11-21T23:59:59Z" : nil }
        end
      end
      milestones = client.milestones
      assert_equal 102, milestones.size
      assert_equal "2026-11-21", milestones.first.fetch("due_on")
      assert_nil milestones[100].fetch("due_on")
      assert_equal "example/two", milestones.last.fetch("repository")
      assert_equal "https://github.com/example/one/milestone/1", milestones.first.fetch("url")
      assert_equal 3, calls.size
      assert calls.all? { |_, query| query[:state] == "all" && query[:per_page] == 100 }
    end

    def test_milestones_does_not_return_partial_results_after_failure
      client = Github::Client.new(token: "test", repositories: ["example/one", "example/two"])
      client.define_singleton_method(:request_json) do |path, _|
        raise Github::Client::RepositoryAccessError, "Unavailable" if path.include?("two")
        []
      end
      assert_raises(Github::Client::RepositoryAccessError) { client.milestones }
      client.define_singleton_method(:request_json) { |*| {} }
      assert_raises(Github::Client::Error) { client.milestones }
    end

    def test_milestone_issues_fetches_open_and_closed_issues_with_pagination_excluding_pull_requests
      client = Github::Client.new(token: "test", repositories: ["example/one"])
      calls = []
      client.define_singleton_method(:request_json) do |path, query|
        calls << [path, query]
        if query[:page] == 1
          Array.new(100) { |i| { "number" => i + 1, "state" => "open" } }
        else
          [{ "number" => 101, "state" => "closed", "closed_at" => "2026-11-21T23:00:00Z" },
            { "number" => 102, "state" => "open", "pull_request" => {} }]
        end
      end
      issues = client.milestone_issues(repository: "example/one", milestone_number: 3)
      assert_equal 101, issues.size
      assert_equal({ "number" => 101, "title" => "Issue #101", "state" => "closed", "closed_on" => "2026-11-21" }, issues.last)
      assert_nil issues.first["closed_on"]
      assert_equal 2, calls.size
      assert calls.all? { |path, query| path == "/repos/example/one/issues" && query[:state] == "all" && query[:milestone] == 3 }
      assert_raises(ArgumentError) { client.milestone_issues(repository: "other/repo", milestone_number: 3) }
    end

    def test_milestone_issue_failure_does_not_return_partial_results
      client = Github::Client.new(token: "test", repositories: ["example/one"])
      client.define_singleton_method(:request_json) do |_, query|
        raise Github::Client::RateLimitError, "Rate limit reached" if query[:page] == 2
        Array.new(100) { |i| { "number" => i + 1, "state" => "open" } }
      end
      assert_raises(Github::Client::RateLimitError) { client.milestone_issues(repository: "example/one", milestone_number: 3) }
      client.define_singleton_method(:request_json) { |*| {} }
      assert_raises(Github::Client::Error) { client.milestone_issues(repository: "example/one", milestone_number: 3) }
    end

    def test_requires_repositories
      client = Github::Client.new(token: "test", repositories: [])
      assert_raises(ArgumentError) { client.open_issues }
      assert_raises(ArgumentError) { client.milestones }
    end
  end
end
