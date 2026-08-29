module GithubIssueOrganizerEngine
  class GithubIdentitiesController < ApplicationController
    rescue_from ArgumentError, with: :render_identity_error
    rescue_from Github::Client::Error, with: :render_github_error

    def show
      @github_identity = current_github_identity || GithubIdentity.new
    end

    def update
      user_id = current_host_user_id || raise(ArgumentError, "No host user is available")
      login = identity_params.fetch(:github_login).to_s.delete_prefix("@").strip
      github_user = github_client.user(login)
      identity = GithubIdentity.find_or_initialize_by(user_id: user_id)
      identity.assign_attributes(
        github_user_id: github_user.fetch("id"),
        github_login: github_user.fetch("login"),
        verified_at: Time.current
      )

      if identity.save
        redirect_to github_identity_path, notice: "GitHub account linked."
      else
        @github_identity = identity
        render :show, status: :unprocessable_entity
      end
    rescue KeyError
      @github_identity = GithubIdentity.new(user_id: user_id, github_login: identity_params[:github_login])
      @github_identity.errors.add(:github_login, "could not be verified")
      render :show, status: :unprocessable_entity
    end

    private

    def identity_params
      params.require(:github_identity).permit(:github_login)
    end

    def render_github_error(error)
      @github_identity = GithubIdentity.new(
        user_id: current_host_user_id,
        github_login: params.dig(:github_identity, :github_login)
      )
      @github_identity.errors.add(:github_login, error.message)
      render :show, status: :unprocessable_entity
    end

    alias_method :render_identity_error, :render_github_error
  end
end
