ENV["RAILS_ENV"] ||= "test"
require_relative "../dummy/config/environment"
require "rails/test_help"

class IssueHistoryTest < ActionDispatch::IntegrationTest
  Snapshot = Struct.new(:captured_at, :priority_counts, :repositories) do
    def total
      priority_counts.values.sum
    end
  end

  test "timelines renders an accessible SVG and exact snapshot counts" do
    counts = GithubIssueOrganizerEngine::IssuePriorityCounts.call([]).merge("Priority: High" => 7)
    snapshots = [Snapshot.new(Time.utc(2026, 9, 8, 10), counts, ["example/one"])]
    render_history(snapshots)

    assert_response :success, request.env["action_dispatch.exception"]&.full_message
    assert_select "head script[src*='github_issue_organizer_engine/application'][defer]", count: 1
    assert_select "head link[href*='github_issue_organizer_engine/application']", count: 1
    assert_select "title", text: "Saved timelines · Team Issue Finder", count: 1
    assert_select "svg[role='img'] title#issue-history-title", text: "Open issues over time by priority"
    assert_select "svg polyline", count: 6
    assert_select "svg circle", count: 6
    assert_select "table tbody tr", count: 1
    assert_select "table td", text: "example/one"
    assert_select "table td", text: "7", count: 2
  end

  test "timelines explains how to start recording history" do
    render_history([])

    assert_response :success
    assert_select "svg", count: 0
    assert_select "p", text: "Set a draft as current to record the first snapshot."
  end

  test "failed GitHub retrieval leaves activation untouched and displays an error" do
    timeline = GithubIssueOrganizerEngine::Timeline.allocate
    timeline.define_singleton_method(:draft?) { true }
    scope = Object.new
    scope.define_singleton_method(:find) { |_| timeline }
    client = Object.new
    client.define_singleton_method(:open_issues) do
      raise GithubIssueOrganizerEngine::Github::Client::RateLimitError, "GitHub rate limit reached"
    end

    GithubIssueOrganizerEngine::Timeline.stub(:includes, scope) do
      GithubIssueOrganizerEngine::Timeline.stub(:transaction, ->(*) { flunk "Activation must not begin after retrieval failure" }) do
        GithubIssueOrganizerEngine::Github::Client.stub(:new, client) do
          patch "/admin/github-issues/timelines/1/make_current"
        end
      end
    end

    assert_redirected_to "/admin/github-issues/timelines"
    assert_equal "GitHub rate limit reached", flash[:alert]
  end

  private

  def render_history(snapshots)
    timeline_scope = Object.new
    timeline_scope.define_singleton_method(:order) { |*| [] }
    GithubIssueOrganizerEngine::Timeline.stub(:includes, timeline_scope) do
      GithubIssueOrganizerEngine::IssueSnapshot.stub(:order, snapshots) do
        get "/admin/github-issues/timelines"
      end
    end
  end
end
