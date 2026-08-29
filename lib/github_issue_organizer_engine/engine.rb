module GithubIssueOrganizerEngine
  class Engine < ::Rails::Engine
    isolate_namespace GithubIssueOrganizerEngine

    initializer "github_issue_organizer_engine.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.paths << root.join("app/assets/javascripts")
      app.config.assets.precompile += %w[
        github_issue_organizer_engine/application.css
        github_issue_organizer_engine/application.js
      ]
    end
  end
end
