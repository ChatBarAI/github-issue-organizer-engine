require "rails/generators"

module GithubIssueOrganizerEngine
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs the GitHub Issue Organizer initializer and mount point"

      def copy_initializer
        template "initializer.rb", "config/initializers/github_issue_organizer_engine.rb"
      end

      def mount_engine
        route 'mount GithubIssueOrganizerEngine::Engine => "/admin/github-issues", as: :github_issue_organizer_engine'
      end

      def show_migration_instruction
        say "Run bin/rails railties:install:migrations FROM=github_issue_organizer_engine and review the copied migrations.", :yellow
      end
    end
  end
end
