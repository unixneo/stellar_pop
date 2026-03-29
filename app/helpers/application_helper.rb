require "open3"

module ApplicationHelper
  def app_version_label
    @app_version_label ||= begin
      version, = Open3.capture2("git", "-C", Rails.root.to_s, "describe", "--tags", "--always", "--dirty")
      normalized = version.to_s.strip
      normalized.present? ? normalized : "unknown"
    rescue StandardError
      "unknown"
    end
  end
end
