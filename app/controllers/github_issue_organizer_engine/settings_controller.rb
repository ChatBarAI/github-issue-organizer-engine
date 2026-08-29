module GithubIssueOrganizerEngine
  class SettingsController < ApplicationController
    def show
      @setting = Setting.current
    end

    def update
      @setting = Setting.current
      @setting.assign_attributes(settings_params)

      if @setting.save
        redirect_to settings_path, notice: "Settings saved."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:setting).permit(:repositories_text, :developer_ids_text)
    end
  end
end
