module GithubIssueOrganizerEngine
  module TimelinesHelper
    def compact_date_range(starts_on, ends_on)
      return I18n.l(starts_on, format: "%B %-d, %Y") if starts_on == ends_on

      if starts_on.year == ends_on.year && starts_on.month == ends_on.month
        "#{I18n.l(starts_on, format: "%B %-d")}–#{I18n.l(ends_on, format: "%-d, %Y")}"
      elsif starts_on.year == ends_on.year
        "#{I18n.l(starts_on, format: "%B %-d")} – #{I18n.l(ends_on, format: "%B %-d, %Y")}"
      else
        "#{I18n.l(starts_on, format: "%B %-d, %Y")} – #{I18n.l(ends_on, format: "%B %-d, %Y")}"
      end
    end

    def timeline_user_name(user, user_id)
      user.try(:fullname).presence || user.try(:email).presence || "User ##{user_id}"
    end

    def timeline_status_label(timeline)
      return "Draft edit" if timeline.draft? && timeline.source_timeline_id.present?

      timeline.status.titleize
    end
  end
end
