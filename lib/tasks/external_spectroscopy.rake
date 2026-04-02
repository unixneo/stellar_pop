require "net/http"
require "uri"

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
end
