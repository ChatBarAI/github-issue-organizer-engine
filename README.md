# GitHub Issue Organizer Engine

A mountable Rails engine for searching issues across configured GitHub
repositories and turning priority and effort labels into draft timelines.

GitHub API requests are made by the Rails server, allowing the engine to work
with private repositories without exposing an access token to the browser. The
host application remains responsible for authentication and authorization.

## AI Generated

Note that this app was largely AI generated, so the usual human attention to
security may be missing. However, since its actions are mostly non-destructive,
it is not high risk.

## Starting Point

This engine is a good starting point, not a universal issue-planning system.
Its labels, scheduling rules, working hours, and status handling reflect one
particular workflow and will probably need customization for your team.

## Features

- Search issues across multiple configured repositories.
- Filter by state, assignee, creator, title, and labels.
- Build a parallel weekday timeline from `Priority:` and `Effort:` labels and developer IDs managed in Settings.
- Prefer an issue's first GitHub assignee when that assignee matches an equally available developer ID.
- Edit saved timelines and reschedule work around developer unavailability measured in hours or days.
- Order scheduled work from Critical through Low priority.
- Show in-review and blocked issues beneath the timeline without allocating developer capacity.
- Rank same-priority issues when they exceed developer capacity, or order them automatically by creation date.
- Report issues that cannot be scheduled because required labels are missing.
- Save every generated timeline and its ordered issues, with Draft, Current, and Obsolete statuses.
- Associate host users with a verified GitHub ID and login.

## Required GitHub Labels

Create the following labels, with these exact case-sensitive names, in every
GitHub repository that the engine will organize.

Each issue to be scheduled needs exactly one supported priority label:

- `Priority: Critical`
- `Priority: High`
- `Priority: Medium`
- `Priority: Low`

It also needs exactly one supported effort label. The scheduler treats one day
as eight working hours:

- `Effort: 4 hrs`
- `Effort: 1 day`
- `Effort: 2 days`
- `Effort: 5 days`
- `Effort: 30 days`

Status labels are optional:

- `Status: Backlog` — schedules the issue normally.
- `Status: In-progress` — schedules the issue ahead of backlog or unlabelled
  issues with the same priority.
- `Status: Review` — lists the issue as informational without allocating
  developer capacity.
- `Status: Blocked` — lists the issue as informational without allocating
  developer capacity.

Issues without a supported priority or effort label are reported as needing
labels instead of being scheduled. Review and blocked issues do not require
priority or effort labels. If an issue has conflicting status labels, blocked
takes precedence over review, which takes precedence over in-progress.

## Requirements

- Ruby 3.2 or later
- Rails 7.2
- A GitHub access token with permission to read the configured repositories

## Installation

Add the engine to the host application's `Gemfile`:

```ruby
gem "github_issue_organizer_engine",
  git: "https://github.com/ChatBarAI/github-issue-organizer-engine.git",
  branch: "main"
```

Then install the engine and its migrations:

```bash
bundle install
bin/rails generate github_issue_organizer_engine:install
bin/rails railties:install:migrations FROM=github_issue_organizer_engine
bin/rails db:migrate
```

Making a draft timeline current retrieves all open issues from the configured
repositories and saves a timestamped count for each priority, plus “No priority”.
This includes blocked, review, and unsized issues regardless of the draft's search
filters. Pull requests are excluded; issues with multiple priority labels count
once under their highest priority. Retrieval must succeed before activation, and
the snapshot and status change are saved in one transaction.

The Timelines page shows an SVG chart of total open issues and each priority over
time, with an expandable table of exact counts and repository lists. Snapshots
are recorded only on activation, survive timeline deletion, and are not backfilled
for older timelines. Changes to configured repositories change the scope of later
snapshots. Existing installations must install and run the new migration using
the commands above.

The generator adds an initializer and mounts the engine at
`/admin/github-issues`. Review both changes before starting the application.

## Configuration

Configure the engine in `config/initializers/github_issue_organizer_engine.rb`:

```ruby
GithubIssueOrganizerEngine.configure do |config|
  config.layout = "application"
  config.user_class_name = "::User"

  config.authorize_with = lambda do
    authenticate_user!
    head :forbidden unless current_user&.admin?
  end

  config.current_user_id = -> { current_user&.id }

  config.github_token = lambda do
    Rails.application.credentials.dig(:github, :issue_organizer_token)
  end

  config.repositories = [
    "your-organization/repository-one",
    "your-organization/repository-two"
  ]
end
```

The initializer list is used as the default. Authorized users can subsequently
manage the shared repository and developer lists from the engine's **Settings** page.

Store the GitHub token in the host application's encrypted credentials:

```yaml
github:
  issue_organizer_token: github_pat_...
```

The callbacks run in the engine controller context, so they can use the host
application's authentication helpers and current user.

The engine uses the host application's Rails process, routes, database, and
asset pipeline. It does not require a separate web service or container.

The shared engine layout includes the engine's CSS and JavaScript, then renders
the host layout selected by `config.layout`. The host layout must include
`<%= yield :head %>` inside its `<head>` and `<%= yield %>` for page content.
Engine pages do not need their own asset include tags.

### Host route helpers in inherited controllers and layouts

The engine is isolated and its controllers inherit from the host application's
`ApplicationController`. During engine requests, unqualified route helpers may
resolve against the engine route set.

Host callbacks and layouts used by the engine must call host application routes
through Rails' `main_app` proxy:

```ruby
main_app.destroy_user_session_path
main_app.admin_root_path
```

Keep engine routes unqualified inside engine views. From host views, use the
engine's mounted route proxy:

```ruby
github_issue_organizer_engine.root_path
```

This is especially relevant when `config.layout` selects a host layout that
contains Devise, navigation, account, or other host-specific links. Route
resolution in this situation is an integration requirement, not a GitHub API
or organizer-engine logic defect.

## Development

```bash
bundle install
bundle exec rake test
```

## License

Available under the MIT License.
