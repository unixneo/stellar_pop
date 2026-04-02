require "net/http"
require "uri"
require "json"

namespace :external do
  desc "Import SIMBAD spectroscopic redshift for one galaxy by local name. Usage: bin/rails \"external:import_simbad_spectroscopy[M87]\" WRITE=true"
  task :import_simbad_spectroscopy, [:galaxy_name] => :environment do |_t, args|
    galaxy_name = args[:galaxy_name].to_s.strip
    if galaxy_name.empty?
      puts "Usage: bin/rails \"external:import_simbad_spectroscopy[M87]\" WRITE=true"
      next
    end

    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    confidence = ENV.fetch("CONFIDENCE", "medium")

    galaxy = Galaxy.find_by(name: galaxy_name)
    unless galaxy
      puts "Galaxy not found: #{galaxy_name.inspect}"
      next
    end

    query_name = galaxy.name.to_s.strip
    encoded_name = URI.encode_www_form_component(query_name)
    urls = [
      "https://simbad.cds.unistra.fr/simbad/sim-id?Ident=#{encoded_name}",
      "https://simbad.harvard.edu/simbad/sim-id?Ident=#{encoded_name}"
    ]

    body = nil
    selected_url = nil

    urls.each do |url|
      begin
        uri = URI(url)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 20
        ) do |http|
          req = Net::HTTP::Get.new(uri)
          http.request(req)
        end

        next unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        selected_url = url
        break
      rescue StandardError
        next
      end
    end

    unless body
      puts "SIMBAD request failed on all endpoints."
      next
    end

    z = nil
    z_err = nil

    with_err = body.match(/z\(spectroscopic\)\s*([+-]?\d+(?:\.\d+)?)\s*\[\s*([+-]?\d+(?:\.\d+)?)\s*\]/i)
    if with_err
      z = with_err[1].to_f
      z_err = with_err[2].to_f
    else
      no_err = body.match(/z\(spectroscopic\)\s*([+-]?\d+(?:\.\d+)?)/i)
      z = no_err[1].to_f if no_err
    end

    if z.nil? || !z.finite?
      puts "No SIMBAD spectroscopic redshift found for #{query_name.inspect}"
      next
    end

    attrs = {
      galaxy_id: galaxy.id,
      current: true,
      redshift_z: z,
      z_err: z_err,
      z_warning: nil,
      redshift_source: "simbad_spectroscopic",
      redshift_confidence: confidence,
      redshift_checked_at: Time.current,
      sdss_dr: galaxy.sdss_dr,
      spec_objid: nil,
      source_release: "SIMBAD",
      match_type: "external_name_exact",
      match_distance_arcsec: nil
    }

    if write_enabled
      spec = GalaxySpectroscopy.create!(attrs)
      puts({ write: true, galaxy: galaxy.name, galaxy_id: galaxy.id, spec_id: spec.id, redshift_z: spec.redshift_z, z_err: spec.z_err, source: spec.redshift_source, confidence: spec.redshift_confidence }.inspect)
    else
      puts({ write: false, galaxy: galaxy.name, galaxy_id: galaxy.id, simbad_url: selected_url, attrs: attrs }.inspect)
      puts "Dry run only. Set WRITE=true to persist."
    end
  rescue => e
    puts "Failed: #{e.class}: #{e.message}"
  end

  desc "Apply SIMBAD z report to galaxy_spectroscopies. Usage: bin/rails external:apply_simbad_z_report WRITE=true REPORT=lib/data/fit/dr19_simbad_z_check.json"
  task :apply_simbad_z_report => :environment do
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    report_path = ENV.fetch("REPORT", "lib/data/fit/dr19_simbad_z_check.json")
    confidence = ENV.fetch("CONFIDENCE", "medium")

    unless File.exist?(report_path)
      puts "Report file not found: #{report_path}"
      next
    end

    payload = JSON.parse(File.read(report_path))
    rows = Array(payload["rows"])

    total = 0
    skipped = 0
    updated = 0
    created = 0

    rows.each do |row|
      z = row["simbad_z"]
      next if z.nil?

      total += 1
      galaxy =
        if row["galaxy_id"].present?
          Galaxy.find_by(id: row["galaxy_id"])
        elsif row["name"].present?
          Galaxy.find_by(name: row["name"])
        end

      unless galaxy
        skipped += 1
        next
      end

      z_value = z.to_f
      z_err_value = row["simbad_z_err"]
      z_err_value = z_err_value.to_f if z_err_value
      z_type = row["simbad_z_type"].to_s.strip.downcase
      source = "simbad_#{z_type.presence || 'z'}"

      attrs = {
        redshift_z: z_value,
        z_err: z_err_value,
        z_warning: nil,
        redshift_source: source,
        redshift_confidence: confidence,
        redshift_checked_at: Time.current,
        sdss_dr: galaxy.sdss_dr,
        spec_objid: nil,
        source_release: "SIMBAD",
        match_type: "external_name_exact",
        match_distance_arcsec: nil,
        current: true
      }

      current = galaxy.galaxy_spectroscopy
      same_as_current =
        current &&
        current.redshift_source.to_s == attrs[:redshift_source].to_s &&
        current.redshift_z.to_f == attrs[:redshift_z].to_f &&
        current.z_err.to_f == attrs[:z_err].to_f

      if same_as_current
        if write_enabled
          current.update!(
            redshift_confidence: attrs[:redshift_confidence],
            redshift_checked_at: attrs[:redshift_checked_at],
            sdss_dr: attrs[:sdss_dr],
            source_release: attrs[:source_release],
            match_type: attrs[:match_type]
          )
        end
        updated += 1
      else
        if write_enabled
          galaxy.galaxy_spectroscopies.create!(attrs)
        end
        created += 1
      end
    end

    puts({
      write: write_enabled,
      report: report_path,
      rows_in_report: rows.size,
      rows_with_simbad_z: total,
      created: created,
      updated: updated,
      skipped: skipped
    }.inspect)
    puts "Dry run only. Set WRITE=true to persist." unless write_enabled
  rescue => e
    puts "Failed: #{e.class}: #{e.message}"
  end

  desc "Fallback AGN classification for unresolved DR19 rows using SIMBAD type metadata. Usage: bin/rails external:classify_simbad_agn_for_unresolved_dr19 WRITE=true REPORT_IN=lib/data/fit/dr19_agn_classification_report.json REPORT_OUT=lib/data/fit/dr19_agn_simbad_fallback_report.json"
  task :classify_simbad_agn_for_unresolved_dr19 => :environment do
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    report_in = ENV.fetch("REPORT_IN", "lib/data/fit/dr19_agn_classification_report.json")
    report_out = ENV.fetch("REPORT_OUT", "lib/data/fit/dr19_agn_simbad_fallback_report.json")
    tap_url = ENV.fetch("SIMBAD_TAP_URL", "https://simbad.cds.unistra.fr/simbad/sim-tap/sync")

    unless File.exist?(report_in)
      puts "Input report not found: #{report_in}"
      next
    end

    input = JSON.parse(File.read(report_in))
    unresolved_rows = Array(input["rows"]).select { |r| r["status"].to_s == "unresolved" }

    if unresolved_rows.empty?
      puts "No unresolved rows found in: #{report_in}"
      next
    end

    summary = {
      generated_at: Time.current.iso8601,
      input_report: report_in,
      write: write_enabled,
      unresolved_input: unresolved_rows.size,
      resolved_by_simbad: 0,
      updated: 0,
      still_unresolved: 0,
      agn_true: 0,
      agn_false: 0
    }
    rows = []

    unresolved_rows.each_with_index do |row, idx|
      galaxy = Galaxy.find_by(id: row["galaxy_id"]) || Galaxy.find_by(name: row["name"])
      unless galaxy
        summary[:still_unresolved] += 1
        rows << row.merge(
          "fallback_status" => "unresolved",
          "fallback_reason" => "galaxy_not_found"
        )
        next
      end

      simbad = fetch_simbad_type_for_name(galaxy.name, tap_url: tap_url)
      if simbad.nil?
        summary[:still_unresolved] += 1
        rows << row.merge(
          "fallback_status" => "unresolved",
          "fallback_reason" => "simbad_lookup_failed"
        )
      else
        agn_flag, confidence, reason = classify_agn_from_simbad_otype(simbad[:otype], simbad[:otypes])
        summary[:resolved_by_simbad] += 1
        summary[:agn_true] += 1 if agn_flag
        summary[:agn_false] += 1 unless agn_flag

        if write_enabled
          galaxy.update!(
            agn: agn_flag,
            agn_source: "simbad_type",
            agn_method: "otype_otypes_rules",
            agn_confidence: confidence,
            agn_checked_at: Time.current
          )
          summary[:updated] += 1
        end

        rows << row.merge(
          "fallback_status" => "resolved",
          "agn" => agn_flag,
          "agn_confidence" => confidence,
          "fallback_reason" => reason,
          "simbad_otype" => simbad[:otype],
          "simbad_otypes" => simbad[:otypes]
        )
      end

      sleep(0.2) if idx < unresolved_rows.length - 1
    end

    output = { summary: summary, rows: rows }
    File.write(report_out, JSON.pretty_generate(output))

    puts({
      write: write_enabled,
      unresolved_input: summary[:unresolved_input],
      resolved_by_simbad: summary[:resolved_by_simbad],
      updated: summary[:updated],
      still_unresolved: summary[:still_unresolved],
      agn_true: summary[:agn_true],
      agn_false: summary[:agn_false],
      report_out: report_out
    }.inspect)
    puts "Dry run only. Set WRITE=true to persist." unless write_enabled
  rescue => e
    puts "Failed: #{e.class}: #{e.message}"
  end

  def fetch_simbad_type_for_name(name, tap_url:)
    safe_name = name.to_s.gsub("'", "''")
    adql = <<~SQL
      SELECT TOP 1 b.main_id, b.otype, b.otypes
      FROM basic AS b
      JOIN ident AS i ON i.oidref = b.oid
      WHERE i.id = '#{safe_name}'
    SQL
      .gsub(/\s+/, " ")
      .strip

    query = URI.encode_www_form(
      "REQUEST" => "doQuery",
      "LANG" => "ADQL",
      "FORMAT" => "TSV",
      "QUERY" => adql
    )
    uri = URI("#{tap_url}?#{query}")

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 10,
      read_timeout: 20
    ) do |http|
      req = Net::HTTP::Get.new(uri)
      http.request(req)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    lines = response.body.to_s.lines.map(&:strip).reject(&:empty?)
    return nil if lines.length < 2

    header = lines[0].split("\t").map(&:strip)
    values = lines[1].split("\t", -1)
    idx_main_id = header.index("main_id")
    idx_otype = header.index("otype")
    idx_otypes = header.index("otypes")
    return nil unless idx_otype

    {
      main_id: idx_main_id ? values[idx_main_id].to_s.strip : nil,
      otype: values[idx_otype].to_s.strip,
      otypes: idx_otypes ? values[idx_otypes].to_s.strip : nil
    }
  rescue StandardError
    nil
  end

  def classify_agn_from_simbad_otype(otype, otypes)
    merged = [otype, otypes].compact.join("|").upcase

    return [true, "high", "simbad_agn_signature"] if merged.match?(/\b(AGN|SYG|SY1|SY2|LINER|BLAZAR|BLLAC|QSO|SEYFERT)\b/)
    return [false, "medium", "simbad_galaxy_non_agn_type"] if merged.match?(/\b(G|GALAXY|HII|SBG|SBNG)\b/)

    [false, "low", "simbad_unknown_type"]
  end
end
