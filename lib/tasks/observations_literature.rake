require "cgi"
require "faraday"
require "json"
require "uri"

namespace :observations do
  desc "Verify each observable against internet search results (DuckDuckGo HTML). Usage: bin/rails observations:verify_observables_web SDSS_DR=DR19 STRICT=true MAX_RESULTS=5 PAUSE_SECONDS=0.8"
  task verify_observables_web: :environment do
    sdss_dr = ENV["SDSS_DR"].to_s.presence
    strict = ActiveModel::Type::Boolean.new.cast(ENV.fetch("STRICT", "true"))
    max_results = ENV.fetch("MAX_RESULTS", "5").to_i.clamp(1, 20)
    pause_seconds = ENV.fetch("PAUSE_SECONDS", "0.8").to_f
    timeout_seconds = ENV.fetch("TIMEOUT_SECONDS", "20").to_i
    max_observations = ENV["MAX_OBSERVATIONS"].to_i

    scope = Observation.includes(:galaxy).order(:id)
    scope = scope.joins(:galaxy).where(galaxies: { sdss_dr: sdss_dr }) if sdss_dr.present?
    observations = scope.to_a
    observations = observations.first(max_observations) if max_observations.positive?

    if observations.empty?
      puts "No observations found for verification."
      next
    end

    conn = Faraday.new(
      url: "https://duckduckgo.com",
      request: { timeout: timeout_seconds, open_timeout: timeout_seconds },
      headers: { "User-Agent" => "StellarPopLiteratureVerifier/1.0" }
    )

    checks = [
      { key: :age_gyr, label: "age", unit: "Gyr" },
      { key: :metallicity_z, label: "metallicity", unit: "Z" },
      { key: :stellar_mass, label: "stellar mass", unit: "Msun" }
    ]

    total_checks = 0
    passed_checks = 0
    failed_checks = []

    observations.each do |observation|
      galaxy = observation.galaxy
      unless galaxy
        failed_checks << "obs_id=#{observation.id} missing galaxy association"
        next
      end

      source = observation.source_paper.to_s.strip
      if source.empty?
        failed_checks << "obs_id=#{observation.id} #{galaxy.name} missing source_paper"
        next
      end

      checks.each do |check|
        value = observation.public_send(check[:key])
        next if value.nil?

        total_checks += 1
        query = build_query(galaxy.name, source, check[:label], check[:unit], value)
        begin
          response = conn.get("/html/", q: query)
          body = response.body.to_s
          snippets = extract_snippets(body).first(max_results)
          result = verify_snippets(snippets, galaxy.name, source, check[:label], value)

          if result[:ok]
            passed_checks += 1
            puts "PASS obs_id=#{observation.id} galaxy=#{galaxy.name} field=#{check[:key]} value=#{value} hits=#{snippets.size}"
          else
            failed_checks << "obs_id=#{observation.id} galaxy=#{galaxy.name} field=#{check[:key]} value=#{value} reason=#{result[:reason]}"
            puts "FAIL obs_id=#{observation.id} galaxy=#{galaxy.name} field=#{check[:key]} value=#{value} reason=#{result[:reason]}"
          end
        rescue StandardError => e
          failed_checks << "obs_id=#{observation.id} galaxy=#{galaxy.name} field=#{check[:key]} value=#{value} error=#{e.class}: #{e.message}"
          puts "FAIL obs_id=#{observation.id} galaxy=#{galaxy.name} field=#{check[:key]} value=#{value} error=#{e.class}: #{e.message}"
        end

        sleep(pause_seconds) if pause_seconds.positive?
      end
    end

    puts "----"
    puts "Web observable verification summary:"
    puts "  observations: #{observations.size}"
    puts "  total observable checks: #{total_checks}"
    puts "  passed: #{passed_checks}"
    puts "  failed: #{failed_checks.size}"

    if failed_checks.any?
      puts "Failures:"
      failed_checks.each { |line| puts "  - #{line}" }
    end

    if strict && failed_checks.any?
      abort("Verification failed (STRICT=true).")
    end
  end

  def build_query(galaxy_name, source_paper, field_label, unit, value)
    value_token =
      if field_label == "stellar mass"
        format("%.3e", value.to_f)
      else
        format("%.3f", value.to_f)
      end
    "#{galaxy_name} #{source_paper} #{field_label} #{unit} #{value_token}"
  end

  def extract_snippets(html)
    compact = html.to_s.gsub(/\s+/, " ")
    blocks = compact.scan(/<a[^>]*class="[^"]*result__a[^"]*"[^>]*>.*?<\/a>.*?(?:<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>.*?<\/a>|<div[^>]*class="[^"]*result__snippet[^"]*"[^>]*>.*?<\/div>)/i).uniq
    blocks.map { |block| strip_tags(block) }.reject(&:empty?)
  end

  def verify_snippets(snippets, galaxy_name, source_paper, field_label, value)
    return { ok: false, reason: "no_search_hits" } if snippets.empty?

    author_hint = source_paper.split(",").first.to_s.split("&").first.to_s.strip
    year_hint = source_paper[/\b(19|20)\d{2}\b/, 0].to_s
    value_tokens = value_tokens_for(field_label, value)

    snippets.each do |snippet|
      text = snippet.downcase
      next unless text.include?(galaxy_name.downcase)
      next unless author_hint.empty? || text.include?(author_hint.downcase)
      next unless year_hint.empty? || text.include?(year_hint)
      next unless text.include?(field_label.split.first)

      has_value = value_tokens.any? { |token| text.include?(token) }
      return { ok: true, reason: "matched_snippet" } if has_value
    end

    { ok: false, reason: "no_snippet_match_for_source_and_value" }
  end

  def value_tokens_for(field_label, value)
    v = value.to_f
    return [format("%.3f", v), format("%.2f", v), format("%.1f", v)] unless field_label == "stellar mass"

    e = format("%.3e", v).downcase
    int = v.round.to_s
    [e, int]
  end

  def strip_tags(input)
    CGI.unescapeHTML(input.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip)
  end
end
