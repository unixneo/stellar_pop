# frozen_string_literal: true

require "fits_parser"
require "json"
require "csv"

module FitsParserTformAliasCompat
  private

  def parse_tform_value(buf, offset, form)
    super(buf, offset, normalize_tform_alias(form))
  end

  def normalize_tform_alias(form)
    case form.to_s.upcase
    when "INT16" then "I"
    when "INT32" then "J"
    when "INT64" then "K"
    when "FLOAT32" then "E"
    when "FLOAT64" then "D"
    else form
    end
  end
end

FitsParser.prepend(FitsParserTformAliasCompat)

namespace :fits do
  desc "Test fits_parser gem against a FITS file: bin/rails 'fits:test[/path/file.fit,/tmp/out.json,json]'"
  task :test, [:path, :out, :format] do |_task, args|
    path = args[:path].presence || ENV["FIT_FILE"]
    out = args[:out].presence || ENV["FIT_OUT"]
    format = (args[:format].presence || ENV["FIT_FORMAT"]).to_s.downcase.presence

    if path.blank?
      abort <<~USAGE
        Missing FITS file path.
        Usage:
          bin/rails "fits:test[/absolute/or/relative/path.fit]"
          bin/rails "fits:test[/path.fit,/tmp/out.json,json]"
          bin/rails "fits:test[/path.fit,/tmp/out.csv,csv]"
        Or:
          FIT_FILE=/path/file.fit FIT_OUT=/tmp/out.json FIT_FORMAT=json bin/rails fits:test
      USAGE
    end

    unless File.file?(path)
      abort "File not found: #{path}"
    end

    parser = FitsParser.new(path)
    hdus = parser.parse_hdus

    puts "File: #{path}"
    puts "HDU count: #{hdus.size}"

    hdus.each_with_index do |hdu, idx|
      header = hdu[:header]
      xtension = header["XTENSION"] || "PRIMARY"

      puts "\nHDU ##{idx}"
      puts "  type: #{xtension}"
      puts "  extname: #{header["EXTNAME"]}" if header["EXTNAME"]
      puts "  naxis: #{header["NAXIS"]}"
      puts "  data_size: #{hdu[:data_size]}"

      next unless xtension == "BINTABLE"

      tfields = Integer(header["TFIELDS"] || 0)
      puts "  bintable columns: #{tfields}"
      (1..tfields).each do |i|
        name = header["TTYPE#{i}"]
        form = header["TFORM#{i}"]
        puts "    - #{i}: #{name} (#{form})"
      end
    end

    next if out.blank?

    inferred_format =
      case File.extname(out).downcase
      when ".json" then "json"
      when ".csv" then "csv"
      end
    output_format = format || inferred_format || "json"

    case output_format
    when "json"
      write_json_output(out, path, hdus)
    when "csv"
      write_csv_output(out, path, hdus)
    else
      abort "Unsupported output format: #{output_format.inspect}. Use json or csv."
    end

    puts "\nWrote parsed output: #{out} (#{output_format})"
  ensure
    parser&.close
  end

  desc "Export full BINTABLE rows to JSON and validate row counts: bin/rails 'fits:export_full[/path.fit,/path/out.json]'"
  task :export_full, [:path, :out] do |_task, args|
    path = args[:path].presence || ENV["FIT_FILE"]
    out = args[:out].presence || ENV["FIT_OUT"]

    if path.blank? || out.blank?
      abort <<~USAGE
        Missing FITS path or output JSON path.
        Usage:
          bin/rails "fits:export_full[/path/file.fit,/path/output.json]"
        Or:
          FIT_FILE=/path/file.fit FIT_OUT=/path/output.json bin/rails fits:export_full
      USAGE
    end

    unless File.file?(path)
      abort "File not found: #{path}"
    end

    parser = FitsParser.new(path)
    hdus = parser.parse_hdus
    summary = fits_hdu_summary(path, hdus)
    validation = stream_full_json_export(parser, path, out, hdus, summary)

    puts "File: #{path}"
    puts "Output: #{out}"
    puts "HDU count: #{hdus.size}"
    puts "BINTABLE HDUs: #{validation[:tables]}"
    puts "Expected rows: #{validation[:expected_rows]}"
    puts "Parsed rows: #{validation[:parsed_rows]}"
    puts "Validation: #{validation[:valid] ? 'OK' : 'FAILED'}"
  ensure
    parser&.close
  end

  desc "Lookup stellar-mass PDF by RA/DEC and output JSON: bin/rails 'fits:mass_pdf_by_radec[146.7,-1.04,1,/tmp/mass.json]'"
  task :mass_pdf_by_radec, [:ra, :dec, :tol_arcsec, :out] do |_task, args|
    ra = Float(args[:ra].presence || ENV["RA"])
    dec = Float(args[:dec].presence || ENV["DEC"])
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    out = args[:out].presence || ENV["FIT_OUT"]

    info_path = Rails.root.join("lib/data/fit/gal_info_dr7_v5_2.fit").to_s
    mass_path = Rails.root.join("lib/data/fit/totlgm_dr7_v5_2.fit").to_s

    unless File.file?(info_path) && File.file?(mass_path)
      abort "Missing FIT files. Expected: #{info_path} and #{mass_path}"
    end

    match = find_best_radec_match(info_path, ra, dec, tol_arcsec)
    unless match
      abort "No object within #{tol_arcsec} arcsec of RA=#{ra}, DEC=#{dec}"
    end

    mass_row = mass_row_at_index(mass_path, match[:index])
    payload = {
      query: {
        ra: ra,
        dec: dec,
        tolerance_arcsec: tol_arcsec
      },
      match: {
        index: match[:index],
        separation_arcsec: match[:separation_arcsec],
        plateid: match[:row]["PLATEID"],
        mjd: match[:row]["MJD"],
        fiberid: match[:row]["FIBERID"],
        ra: match[:row]["RA"],
        dec: match[:row]["DEC"]
      },
      pdf_log_mstar: json_safe_value(mass_row)
    }

    json = JSON.pretty_generate(payload)
    puts json
    File.write(out, json) if out.present?
    puts "\nWrote JSON: #{out}" if out.present?
  rescue ArgumentError
    abort <<~USAGE
      Invalid/missing RA DEC.
      Usage:
        bin/rails "fits:mass_pdf_by_radec[RA,DEC]"
        bin/rails "fits:mass_pdf_by_radec[RA,DEC,TOL_ARCSEC,/tmp/mass.json]"
      Or:
        RA=146.7 DEC=-1.04 TOL_ARCSEC=1 FIT_OUT=/tmp/mass.json bin/rails fits:mass_pdf_by_radec
    USAGE
  end

  desc "Crossmatch DR19 galaxies against gal_info FIT by coordinates: bin/rails 'fits:crossmatch_dr19_gal_info[1,false,/tmp/report.json]'"
  task :crossmatch_dr19_gal_info, [:tol_arcsec, :write, :out] => :environment do |_task, args|
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    write_updates = ActiveModel::Type::Boolean.new.cast(args[:write].presence || ENV["WRITE"])
    out = args[:out].presence || ENV["FIT_OUT"]

    info_path = Rails.root.join("lib/data/fit/gal_info_dr7_v5_2.fit").to_s
    abort "Missing FIT file: #{info_path}" unless File.file?(info_path)

    galaxies = Galaxy.where(sdss_dr: "DR19").where.not(ra: nil, dec: nil).order(:id).to_a
    abort "No DR19 galaxies with RA/DEC found" if galaxies.empty?

    rows_by_ra = load_gal_info_rows_for_matching(info_path)
    puts "Loaded gal_info rows: #{rows_by_ra.size}"
    puts "DR19 galaxies to check: #{galaxies.size}"

    matched = 0
    unmatched = 0
    updated = 0
    details = []

    galaxies.each do |galaxy|
      match = find_best_match_by_radec(rows_by_ra, galaxy.ra.to_f, galaxy.dec.to_f, tol_arcsec)

      if match
        matched += 1
        note = "gal_info match within #{tol_arcsec}\" (idx=#{match[:index]}, plate=#{match[:plateid]}, mjd=#{match[:mjd]}, fiber=#{match[:fiberid]})"
        details << {
          galaxy_id: galaxy.id,
          name: galaxy.name,
          ra: galaxy.ra,
          dec: galaxy.dec,
          matched: true,
          separation_arcsec: match[:separation_arcsec],
          fit_index: match[:index],
          plateid: match[:plateid],
          mjd: match[:mjd],
          fiberid: match[:fiberid]
        }

        if write_updates
          galaxy.update!(
            id_match_quality: "coord_validated",
            id_match_distance_arcsec: match[:separation_arcsec],
            id_match_note: note
          )
          updated += 1
        end
      else
        unmatched += 1
        note = "No gal_info match within #{tol_arcsec}\""
        details << {
          galaxy_id: galaxy.id,
          name: galaxy.name,
          ra: galaxy.ra,
          dec: galaxy.dec,
          matched: false
        }

        if write_updates
          galaxy.update!(
            id_match_quality: "unverified",
            id_match_distance_arcsec: nil,
            id_match_note: note
          )
          updated += 1
        end
      end
    end

    payload = {
      file: info_path,
      tolerance_arcsec: tol_arcsec,
      dry_run: !write_updates,
      galaxies_checked: galaxies.size,
      matched: matched,
      unmatched: unmatched,
      updated: updated,
      details: details
    }

    puts JSON.pretty_generate(payload.except(:details))
    puts "Sample matches:"
    details.first(5).each { |d| puts "  - #{d.inspect}" }

    if out.present?
      File.write(out, JSON.pretty_generate(payload))
      puts "Wrote report: #{out}"
    end
  rescue ArgumentError
    abort <<~USAGE
      Invalid args.
      Usage:
        bin/rails "fits:crossmatch_dr19_gal_info[1,false,/tmp/report.json]"
      Or:
        TOL_ARCSEC=1 WRITE=true FIT_OUT=/tmp/report.json bin/rails fits:crossmatch_dr19_gal_info
    USAGE
  end

  desc "Parse crossmatch report and pull stellar-mass PDFs from totlgm FIT: bin/rails 'fits:mass_pdfs_from_report[/path/report.json,false,/path/output.json]'"
  task :mass_pdfs_from_report, [:report, :write, :out] do |_task, args|
    report_path = args[:report].presence || ENV["REPORT"] || Rails.root.join("lib/data/fit/dr19_gal_info_crossmatch_report.json").to_s
    write_output = ActiveModel::Type::Boolean.new.cast(args[:write].presence || ENV["WRITE"])
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/dr19_gal_info_stellar_mass_pdfs.json").to_s

    abort "Report not found: #{report_path}" unless File.file?(report_path)

    report = JSON.parse(File.read(report_path))
    details = report.fetch("details", [])
    matched = details.select { |d| d["matched"] && d["fit_index"] }
    abort "No matched entries with fit_index found in report: #{report_path}" if matched.empty?

    mass_path = Rails.root.join("lib/data/fit/totlgm_dr7_v5_2.fit").to_s
    abort "Missing FIT file: #{mass_path}" unless File.file?(mass_path)

    indices = matched.map { |d| Integer(d["fit_index"]) }.uniq.sort
    mass_rows_by_index = mass_rows_at_indices(mass_path, indices)

    entries = matched.map do |m|
      idx = Integer(m["fit_index"])
      {
        galaxy_id: m["galaxy_id"],
        name: m["name"],
        ra: m["ra"],
        dec: m["dec"],
        fit_index: idx,
        separation_arcsec: m["separation_arcsec"],
        plateid: m["plateid"],
        mjd: m["mjd"],
        fiberid: m["fiberid"],
        pdf_log_mstar: json_safe_value(mass_rows_by_index[idx])
      }
    end

    payload = {
      source_report: report_path,
      source_mass_fit: mass_path,
      dry_run: !write_output,
      galaxies_in_report: details.size,
      matched_in_report: matched.size,
      pdfs_resolved: entries.count { |e| !e[:pdf_log_mstar].nil? },
      entries: entries
    }

    puts JSON.pretty_generate(payload.except(:entries))
    puts "Sample PDF entries:"
    entries.first(5).each { |e| puts "  - #{e.inspect}" }

    if write_output
      File.write(out, JSON.pretty_generate(payload))
      puts "Wrote stellar-mass PDF JSON: #{out}"
    else
      puts "Dry run: no output file written (set write=true to persist JSON)"
    end
  rescue ArgumentError, KeyError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:mass_pdfs_from_report[/path/report.json,false,/path/output.json]"
      Or:
        REPORT=/path/report.json WRITE=true FIT_OUT=/path/output.json bin/rails fits:mass_pdfs_from_report
    USAGE
  end

  desc "Compare stellar-mass PDFs (log M*) with observations.stellar_mass (Msun): bin/rails 'fits:compare_mass_pdfs_with_observations[/path/pdfs.json,false,/path/compare.json]'"
  task :compare_mass_pdfs_with_observations, [:pdfs, :write, :out] => :environment do |_task, args|
    pdfs_path = args[:pdfs].presence || ENV["PDFS"] || Rails.root.join("lib/data/fit/dr19_gal_info_stellar_mass_pdfs.json").to_s
    write_output = ActiveModel::Type::Boolean.new.cast(args[:write].presence || ENV["WRITE"])
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/dr19_mass_pdf_vs_observations.json").to_s

    abort "PDF JSON not found: #{pdfs_path}" unless File.file?(pdfs_path)

    data = JSON.parse(File.read(pdfs_path))
    entries = data.fetch("entries", [])
    abort "No entries found in #{pdfs_path}" if entries.empty?

    comparisons = entries.map do |entry|
      compare_pdf_entry_with_observations(entry)
    end

    with_observations = comparisons.select { |c| c[:observation_count].to_i.positive? && !c[:observed_log_mstar].nil? }
    within_68 = with_observations.count { |c| c[:within_p16_p84] }
    within_95 = with_observations.count { |c| c[:within_p2p5_p97p5] }

    payload = {
      source_pdfs: pdfs_path,
      dry_run: !write_output,
      entries_total: comparisons.size,
      entries_with_observations: with_observations.size,
      entries_without_observations: comparisons.size - with_observations.size,
      within_p16_p84: within_68,
      within_p2p5_p97p5: within_95,
      comparisons: comparisons
    }

    puts JSON.pretty_generate(payload.except(:comparisons))
    puts "Sample comparisons:"
    comparisons.first(5).each { |c| puts "  - #{c.inspect}" }

    if write_output
      File.write(out, JSON.pretty_generate(payload))
      puts "Wrote comparison JSON: #{out}"
    else
      puts "Dry run: no output file written (set write=true to persist JSON)"
    end
  rescue ArgumentError, KeyError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:compare_mass_pdfs_with_observations[/path/pdfs.json,false,/path/compare.json]"
      Or:
      PDFS=/path/pdfs.json WRITE=true FIT_OUT=/path/compare.json bin/rails fits:compare_mass_pdfs_with_observations
    USAGE
  end

  desc "Crossmatch local galaxies to MaNGA Pipe3D by coordinates and write JSON: bin/rails 'fits:crossmatch_pipe3d_galaxies[1,/tmp/pipe3d_matches.json,0]'"
  task :crossmatch_pipe3d_galaxies, [:tol_arcsec, :out, :limit] => :environment do |_task, args|
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/pipe3d_crossmatch.json").to_s
    limit = Integer(args[:limit].presence || ENV["LIMIT"] || 0)

    pipe3d_path = Rails.root.join("lib/data/fit/SDSS17Pipe3D_v3_1_1.fits").to_s
    abort "Missing FIT file: #{pipe3d_path}" unless File.file?(pipe3d_path)

    galaxies = Galaxy.where.not(ra: nil, dec: nil).order(:id)
    galaxies = galaxies.limit(limit) if limit.positive?
    galaxies = galaxies.to_a
    abort "No galaxies with RA/DEC found in main DB" if galaxies.empty?

    puts "Loading Pipe3D GAL_PROPERTIES rows (objra/objdec)..."
    rows_by_ra = load_pipe3d_rows_for_matching(pipe3d_path)
    puts "Pipe3D rows loaded: #{rows_by_ra.size}"
    puts "Galaxies checked: #{galaxies.size}"

    rows_by_sdss_objid = rows_by_ra.each_with_object({}) do |row, h|
      next if row[:sdss_objid].blank?
      h[row[:sdss_objid]] ||= []
      h[row[:sdss_objid]] << row
    end

    matched = 0
    unmatched = 0
    matched_by_objid = 0
    matched_by_radec = 0
    matches = []

    galaxies.each do |galaxy|
      normalized_objid = normalize_sdss_objid(galaxy.sdss_objid)
      m = nil
      match_type = nil

      if normalized_objid.present?
        objid_rows = rows_by_sdss_objid[normalized_objid]
        if objid_rows.present?
          m = best_row_by_separation(objid_rows, galaxy.ra.to_f, galaxy.dec.to_f)
          match_type = "sdss_objid" if m
        end
      end

      unless m
        m = find_best_match_by_radec(rows_by_ra, galaxy.ra.to_f, galaxy.dec.to_f, tol_arcsec)
        match_type = "radec" if m
      end

      if m
        matched += 1
        matched_by_objid += 1 if match_type == "sdss_objid"
        matched_by_radec += 1 if match_type == "radec"
        matches << {
          galaxy_id: galaxy.id,
          galaxy_name: galaxy.name,
          galaxy_sdss_objid: galaxy.sdss_objid,
          galaxy_ra: galaxy.ra,
          galaxy_dec: galaxy.dec,
          match_type: match_type,
          separation_arcsec: m[:separation_arcsec],
          pipe3d_index: m[:index],
          pipe3d_sdss_objid: m[:sdss_objid],
          pipe3d_name: m[:name],
          pipe3d_plateifu: m[:plateifu],
          pipe3d_mangaid: m[:mangaid],
          pipe3d_ra: m[:ra],
          pipe3d_dec: m[:dec],
          pipe3d_age_lw_re_fit_gyr: m[:age_lw_re_fit],
          pipe3d_age_mw_re_fit_gyr: m[:age_mw_re_fit],
          pipe3d_zh_lw_re_fit: m[:zh_lw_re_fit],
          pipe3d_zh_mw_re_fit: m[:zh_mw_re_fit],
          pipe3d_log_mass: m[:log_mass]
        }
      else
        unmatched += 1
      end
    end

    payload = {
      source_fit: pipe3d_path,
      tolerance_arcsec: tol_arcsec,
      galaxies_checked: galaxies.size,
      matched: matched,
      matched_by_objid: matched_by_objid,
      matched_by_radec: matched_by_radec,
      unmatched: unmatched,
      matches: matches
    }

    File.write(out, JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload.except(:matches))
    puts "Sample matches:"
    matches.first(10).each { |row| puts "  - #{row.inspect}" }
    puts "Wrote JSON: #{out}"
  rescue ArgumentError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:crossmatch_pipe3d_galaxies[1,/tmp/pipe3d_matches.json,0]"
      Or:
        TOL_ARCSEC=1 FIT_OUT=/tmp/pipe3d_matches.json LIMIT=0 bin/rails fits:crossmatch_pipe3d_galaxies
    USAGE
  end

  desc "Crossmatch local galaxies to MaNGA FIREFLY globalprop by coordinates and write JSON: bin/rails 'fits:crossmatch_firefly_galaxies[/path/firefly.fits,1,/tmp/firefly_matches.json,0]'"
  task :crossmatch_firefly_galaxies, [:path, :tol_arcsec, :out, :limit] => :environment do |_task, args|
    firefly_path = args[:path].presence || ENV["FIREFLY_FIT"] || Rails.root.join("lib/data/fit/manga-firefly-globalprop-v3_1_1-mastar.fits").to_s
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/firefly_crossmatch.json").to_s
    limit = Integer(args[:limit].presence || ENV["LIMIT"] || 0)

    abort "Missing FIT file: #{firefly_path}" unless File.file?(firefly_path)

    galaxies = Galaxy.where.not(ra: nil, dec: nil).order(:id)
    galaxies = galaxies.limit(limit) if limit.positive?
    galaxies = galaxies.to_a
    abort "No galaxies with RA/DEC found in main DB" if galaxies.empty?

    puts "Loading FIREFLY rows (GALAXY_INFO + GLOBAL_PARAMETERS)..."
    rows_by_ra = load_firefly_global_rows_for_matching(firefly_path)
    puts "FIREFLY rows loaded: #{rows_by_ra.size}"
    puts "Galaxies checked: #{galaxies.size}"

    matched = 0
    unmatched = 0
    matches = []

    galaxies.each do |galaxy|
      m = find_best_match_by_radec(rows_by_ra, galaxy.ra.to_f, galaxy.dec.to_f, tol_arcsec)
      if m
        matched += 1
        matches << {
          galaxy_id: galaxy.id,
          galaxy_name: galaxy.name,
          galaxy_sdss_objid: galaxy.sdss_objid,
          galaxy_ra: galaxy.ra,
          galaxy_dec: galaxy.dec,
          separation_arcsec: m[:separation_arcsec],
          firefly_index: m[:index],
          firefly_mangaid: m[:mangaid],
          firefly_plateifu: m[:plateifu],
          firefly_ra: m[:ra],
          firefly_dec: m[:dec],
          firefly_redshift: m[:redshift],
          firefly_photometric_mass: m[:photometric_mass],
          firefly_lw_age_1re: m[:lw_age_1re],
          firefly_mw_age_1re: m[:mw_age_1re],
          firefly_lw_z_1re: m[:lw_z_1re],
          firefly_mw_z_1re: m[:mw_z_1re]
        }
      else
        unmatched += 1
      end
    end

    payload = {
      source_fit: firefly_path,
      tolerance_arcsec: tol_arcsec,
      galaxies_checked: galaxies.size,
      matched: matched,
      unmatched: unmatched,
      matches: matches
    }

    File.write(out, JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload.except(:matches))
    puts "Sample matches:"
    matches.first(10).each { |row| puts "  - #{row.inspect}" }
    puts "Wrote JSON: #{out}"
  rescue ArgumentError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:crossmatch_firefly_galaxies[/path/firefly.fits,1,/tmp/firefly_matches.json,0]"
      Or:
        FIREFLY_FIT=/path/firefly.fits TOL_ARCSEC=1 FIT_OUT=/tmp/firefly_matches.json LIMIT=0 bin/rails fits:crossmatch_firefly_galaxies
    USAGE
  end

  desc "Crossmatch local galaxies to DR16 eBOSS FIREFLY by SDSS ObjID or RA/DEC and write JSON: bin/rails 'fits:crossmatch_eboss_firefly_galaxies[/path/sdss_firefly-26.fits,1,/tmp/eboss_firefly.json,0,0]'"
  task :crossmatch_eboss_firefly_galaxies, [:path, :tol_arcsec, :out, :limit, :max_rows] => :environment do |_task, args|
    path = args[:path].presence || ENV["FIREFLY_FIT"] || Rails.root.join("lib/data/fit/sdss_firefly-26.fits").to_s
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/eboss_firefly_crossmatch.json").to_s
    limit = Integer(args[:limit].presence || ENV["LIMIT"] || 0)
    max_rows = Integer(args[:max_rows].presence || ENV["MAX_ROWS"] || 0)

    abort "Missing FIT file: #{path}" unless File.file?(path)

    galaxies = Galaxy.where.not(ra: nil, dec: nil).order(:id)
    galaxies = galaxies.limit(limit) if limit.positive?
    galaxies = galaxies.to_a
    abort "No galaxies with RA/DEC found in main DB" if galaxies.empty?

    galaxies_by_objid = galaxies.each_with_object({}) do |g, h|
      objid = normalize_sdss_objid(g.sdss_objid)
      next if objid.blank?
      h[objid] ||= []
      h[objid] << g
    end

    exact_by_galaxy = {}
    radec_by_galaxy = {}
    rows_scanned = 0

    needed = %w[
      BESTOBJID FLUXOBJID TARGETOBJID
      PLUG_RA PLUG_DEC PLATE MJD FIBERID
      CLASS SUBCLASS Z Z_ERR SPECOBJID
      Chabrier_MILES_age_massW
      Chabrier_MILES_metallicity_massW
      Chabrier_MILES_stellar_mass
    ]

    FitsParser.open(path) do |parser|
      hdu = parser.parse_hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" && h[:header]["EXTNAME"] == "Joined" }
      abort "Joined BINTABLE not found in #{path}" unless hdu

      parser.instance_variable_get(:@io).seek(hdu[:data_pos])
      row_len = Integer(hdu[:header]["NAXIS1"] || 0)
      total_rows = Integer(hdu[:header]["NAXIS2"] || 0)
      use_rows = max_rows.positive? ? [max_rows, total_rows].min : total_rows
      offsets = bintable_column_offsets(hdu[:header], needed)

      puts "Scanning FIREFLY rows: #{use_rows} (of #{total_rows})"

      use_rows.times do |idx|
        row_buf = parser.instance_variable_get(:@io).read(row_len)
        break if row_buf.nil? || row_buf.bytesize != row_len
        rows_scanned = idx + 1

        rec = decode_row_subset(row_buf, offsets)
        ra = float_or_nil(rec["PLUG_RA"])
        dec = float_or_nil(rec["PLUG_DEC"])
        next if ra.nil? || dec.nil?

        objids = [
          normalize_sdss_objid(rec["BESTOBJID"]),
          normalize_sdss_objid(rec["FLUXOBJID"]),
          normalize_sdss_objid(rec["TARGETOBJID"])
        ].compact.uniq

        unless objids.empty?
          objids.each do |oid|
            next unless galaxies_by_objid.key?(oid)
            galaxies_by_objid[oid].each do |g|
              sep = angular_separation_arcsec(g.ra.to_f, g.dec.to_f, ra, dec)
              prev = exact_by_galaxy[g.id]
              if prev.nil? || sep < prev[:separation_arcsec]
                exact_by_galaxy[g.id] = build_eboss_match_record(g, rec, ra, dec, sep, idx, "sdss_objid")
              end
            end
          end
        end

        galaxies.each do |g|
          sep = angular_separation_arcsec(g.ra.to_f, g.dec.to_f, ra, dec)
          next if sep > tol_arcsec
          prev = radec_by_galaxy[g.id]
          if prev.nil? || sep < prev[:separation_arcsec]
            radec_by_galaxy[g.id] = build_eboss_match_record(g, rec, ra, dec, sep, idx, "radec")
          end
        end
      end
    end

    matches = []
    matched_by_objid = 0
    matched_by_radec = 0

    galaxies.each do |g|
      m = exact_by_galaxy[g.id] || radec_by_galaxy[g.id]
      next unless m
      matched_by_objid += 1 if m[:match_type] == "sdss_objid"
      matched_by_radec += 1 if m[:match_type] == "radec"
      matches << m
    end

    payload = {
      source_fit: path,
      tolerance_arcsec: tol_arcsec,
      rows_scanned: rows_scanned,
      max_rows: max_rows.positive? ? max_rows : nil,
      galaxies_checked: galaxies.size,
      matched: matches.size,
      matched_by_objid: matched_by_objid,
      matched_by_radec: matched_by_radec,
      unmatched: galaxies.size - matches.size,
      matches: matches
    }

    File.write(out, JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload.except(:matches))
    puts "Sample matches:"
    matches.first(10).each { |row| puts "  - #{row.inspect}" }
    puts "Wrote JSON: #{out}"
  rescue ArgumentError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:crossmatch_eboss_firefly_galaxies[/path/sdss_firefly-26.fits,1,/tmp/eboss_firefly.json,0,0]"
      Or:
        FIREFLY_FIT=/path/sdss_firefly-26.fits TOL_ARCSEC=1 FIT_OUT=/tmp/eboss_firefly.json LIMIT=0 MAX_ROWS=0 bin/rails fits:crossmatch_eboss_firefly_galaxies
    USAGE
  end

  desc "Compare matched DR16 eBOSS FIREFLY age/Z/mass with observations: bin/rails 'fits:compare_eboss_firefly_with_observations[/path/eboss_firefly_crossmatch.json,/tmp/compare.json]'"
  task :compare_eboss_firefly_with_observations, [:crossmatch, :out] => :environment do |_task, args|
    crossmatch_path = args[:crossmatch].presence || ENV["CROSSMATCH"] || Rails.root.join("lib/data/fit/eboss_firefly_crossmatch.json").to_s
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/eboss_firefly_vs_observations.json").to_s

    abort "Crossmatch JSON not found: #{crossmatch_path}" unless File.file?(crossmatch_path)

    data = JSON.parse(File.read(crossmatch_path))
    matches = data.fetch("matches", [])
    abort "No matches in #{crossmatch_path}" if matches.empty?

    comparisons = matches.map { |m| compare_eboss_match_with_observations(m) }

    with_age_obs = comparisons.count { |c| !c[:obs_age_gyr].nil? }
    with_z_obs = comparisons.count { |c| !c[:obs_metallicity_z].nil? }
    with_mass_obs = comparisons.count { |c| !c[:obs_stellar_mass_msun].nil? }

    payload = {
      source_crossmatch: crossmatch_path,
      entries_total: comparisons.size,
      with_age_observation: with_age_obs,
      with_metallicity_observation: with_z_obs,
      with_stellar_mass_observation: with_mass_obs,
      comparisons: comparisons
    }

    File.write(out, JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload.except(:comparisons))
    puts "Sample comparisons:"
    comparisons.first(10).each { |c| puts "  - #{c.inspect}" }
    puts "Wrote JSON: #{out}"
  rescue ArgumentError, KeyError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "fits:compare_eboss_firefly_with_observations[/path/eboss_firefly_crossmatch.json,/tmp/compare.json]"
      Or:
        CROSSMATCH=/path/eboss_firefly_crossmatch.json FIT_OUT=/tmp/compare.json bin/rails fits:compare_eboss_firefly_with_observations
    USAGE
  end
end

def write_json_output(out, path, hdus)
  payload = {
    file: path,
    hdu_count: hdus.size,
    hdus: fits_hdu_summary(path, hdus)
  }

  File.write(out, JSON.pretty_generate(payload))
end

def write_csv_output(out, path, hdus)
  CSV.open(out, "wb") do |csv|
    csv << ["file", "hdu_index", "type", "extname", "naxis", "naxis1", "naxis2", "tfields", "data_pos", "data_size"]
    hdus.each_with_index do |hdu, idx|
      header = hdu[:header]
      csv << [
        path,
        idx,
        header["XTENSION"] || "PRIMARY",
        header["EXTNAME"],
        header["NAXIS"],
        header["NAXIS1"],
        header["NAXIS2"],
        header["TFIELDS"],
        hdu[:data_pos],
        hdu[:data_size]
      ]
    end
  end
end

def fits_hdu_summary(path, hdus)
  hdus.map.with_index do |hdu, idx|
    header = hdu[:header]
    {
      file: path,
      index: idx,
      type: header["XTENSION"] || "PRIMARY",
      extname: header["EXTNAME"],
      naxis: header["NAXIS"],
      naxis1: header["NAXIS1"],
      naxis2: header["NAXIS2"],
      tfields: header["TFIELDS"],
      data_pos: hdu[:data_pos],
      data_size: hdu[:data_size],
      header: header
    }
  end
end

def stream_full_json_export(parser, path, out, hdus, summary)
  total_expected_rows = 0
  total_parsed_rows = 0
  table_count = 0

  File.open(out, "wb") do |f|
    f << "{\"file\":#{JSON.generate(path)},\"hdu_count\":#{hdus.size},\"hdus\":#{JSON.generate(summary)},\"bintables\":["
    first_table = true

    hdus.each_with_index do |hdu, idx|
      header = hdu[:header]
      next unless header["XTENSION"] == "BINTABLE"

      columns = parser.bintable_columns(hdu)
      expected_rows = Integer(header["NAXIS2"] || 0)
      parsed_rows = 0

      f << "," unless first_table
      first_table = false

      f << "{\"hdu_index\":#{idx},\"columns\":#{JSON.generate(columns)},\"rows\":["
      first_row = true
      parser.each_bintable_row(hdu) do |row|
        f << "," unless first_row
        first_row = false
        f << JSON.generate(json_safe_value(row))
        parsed_rows += 1
      end
      f << "],\"expected_rows\":#{expected_rows},\"parsed_rows\":#{parsed_rows},\"valid\":#{parsed_rows == expected_rows}}"

      table_count += 1
      total_expected_rows += expected_rows
      total_parsed_rows += parsed_rows
    end

    valid = total_expected_rows == total_parsed_rows
    f << "],\"validation\":#{JSON.generate({
      tables: table_count,
      expected_rows: total_expected_rows,
      parsed_rows: total_parsed_rows,
      valid: valid
    })}}"
  end

  {
    tables: table_count,
    expected_rows: total_expected_rows,
    parsed_rows: total_parsed_rows,
    valid: total_expected_rows == total_parsed_rows
  }
end

def json_safe_value(value)
  case value
  when Hash
    value.transform_values { |v| json_safe_value(v) }
  when Array
    value.map { |v| json_safe_value(v) }
  when Float
    value.finite? ? value : nil
  else
    value
  end
end

def find_best_radec_match(info_path, ra_target, dec_target, tol_arcsec)
  best = nil

  FitsParser.open(info_path) do |parser|
    hdu = parser.parse_hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" }
    parser.each_bintable_row(hdu).with_index do |row, idx|
      row_ra = row["RA"]
      row_dec = row["DEC"]
      next if row_ra.nil? || row_dec.nil?

      separation = angular_separation_arcsec(ra_target, dec_target, row_ra, row_dec)
      if best.nil? || separation < best[:separation_arcsec]
        best = { index: idx, separation_arcsec: separation, row: row }
      end
    end
  end

  return nil if best.nil? || best[:separation_arcsec] > tol_arcsec

  best
end

def mass_row_at_index(mass_path, target_index)
  FitsParser.open(mass_path) do |parser|
    hdu = parser.parse_hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" }
    parser.each_bintable_row(hdu).with_index do |row, idx|
      return row if idx == target_index
    end
  end

  raise "Failed to read mass row at index #{target_index}"
end

def angular_separation_arcsec(ra1_deg, dec1_deg, ra2_deg, dec2_deg)
  ra1 = ra1_deg * Math::PI / 180.0
  dec1 = dec1_deg * Math::PI / 180.0
  ra2 = ra2_deg * Math::PI / 180.0
  dec2 = dec2_deg * Math::PI / 180.0

  sin_ddec = Math.sin((dec2 - dec1) / 2.0)
  sin_dra = Math.sin((ra2 - ra1) / 2.0)
  a = (sin_ddec * sin_ddec) + Math.cos(dec1) * Math.cos(dec2) * (sin_dra * sin_dra)
  a = [[a, 0.0].max, 1.0].min
  c = 2.0 * Math.asin(Math.sqrt(a))
  c * (180.0 / Math::PI) * 3600.0
end

def load_gal_info_rows_for_matching(info_path)
  rows = []

  FitsParser.open(info_path) do |parser|
    hdu = parser.parse_hdus.find { |x| x[:header]["XTENSION"] == "BINTABLE" }
    parser.each_bintable_row(hdu).with_index do |row, idx|
      ra = row["RA"]
      dec = row["DEC"]
      next if ra.nil? || dec.nil?

      rows << {
        ra: ra.to_f,
        dec: dec.to_f,
        index: idx,
        plateid: row["PLATEID"],
        mjd: row["MJD"],
        fiberid: row["FIBERID"]
      }
    end
  end

  rows.sort_by { |r| r[:ra] }
end

def load_pipe3d_rows_for_matching(pipe3d_path)
  rows = []

  FitsParser.open(pipe3d_path) do |parser|
    hdu = parser.parse_hdus.find { |x| x[:header]["XTENSION"] == "BINTABLE" && x[:header]["EXTNAME"] == "GAL_PROPERTIES" }
    raise "Pipe3D GAL_PROPERTIES BINTABLE not found: #{pipe3d_path}" unless hdu

    parser.each_bintable_row(hdu).with_index do |row, idx|
      ra = row["objra"]
      dec = row["objdec"]
      next if ra.nil? || dec.nil?

      rows << {
        index: idx,
        ra: ra.to_f,
        dec: dec.to_f,
        sdss_objid: normalize_sdss_objid(row["sdss_objid"] || row["OBJID"] || row["objid"] || row["bestobjid"] || row["BESTOBJID"]),
        name: row["name"],
        plateifu: row["plateifu"],
        mangaid: row["mangaid"],
        age_lw_re_fit: row["Age_LW_Re_fit"],
        age_mw_re_fit: row["Age_MW_Re_fit"],
        zh_lw_re_fit: row["ZH_LW_Re_fit"],
        zh_mw_re_fit: row["ZH_MW_Re_fit"],
        log_mass: row["log_Mass"]
      }
    end
  end

  rows.sort_by { |r| r[:ra] }
end

def load_firefly_global_rows_for_matching(firefly_path)
  info_rows = []
  global_rows = []

  FitsParser.open(firefly_path) do |parser|
    hdus = parser.parse_hdus
    info_hdu = hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" && h[:header]["EXTNAME"] == "GALAXY_INFO" }
    global_hdu = hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" && h[:header]["EXTNAME"] == "GLOBAL_PARAMETERS" }
    raise "FIREFLY GALAXY_INFO BINTABLE not found: #{firefly_path}" unless info_hdu
    raise "FIREFLY GLOBAL_PARAMETERS BINTABLE not found: #{firefly_path}" unless global_hdu

    parser.each_bintable_row(info_hdu) { |row| info_rows << row }
    parser.each_bintable_row(global_hdu) { |row| global_rows << row }
  end

  raise "FIREFLY row count mismatch: info=#{info_rows.size}, global=#{global_rows.size}" unless info_rows.size == global_rows.size

  rows = []
  info_rows.each_with_index do |info, idx|
    global = global_rows[idx]
    ra = info["OBJRA"]
    dec = info["OBJDEC"]
    next if ra.nil? || dec.nil?

    rows << {
      index: idx,
      ra: ra.to_f,
      dec: dec.to_f,
      mangaid: info["MANGAID"],
      plateifu: info["PLATEIFU"],
      redshift: info["REDSHIFT"],
      photometric_mass: info["PHOTOMETRIC_MASS"],
      lw_age_1re: global["LW_AGE_1Re"],
      mw_age_1re: global["MW_AGE_1Re"],
      lw_z_1re: global["LW_Z_1Re"],
      mw_z_1re: global["MW_Z_1Re"]
    }
  end

  rows.sort_by { |r| r[:ra] }
end

def build_eboss_match_record(galaxy, rec, ra, dec, sep, idx, match_type)
  {
    galaxy_id: galaxy.id,
    galaxy_name: galaxy.name,
    galaxy_sdss_objid: galaxy.sdss_objid,
    galaxy_ra: galaxy.ra,
    galaxy_dec: galaxy.dec,
    match_type: match_type,
    separation_arcsec: sep,
    firefly_row_index: idx,
    firefly_bestobjid: rec["BESTOBJID"],
    firefly_fluxobjid: rec["FLUXOBJID"],
    firefly_targetobjid: rec["TARGETOBJID"],
    firefly_specobjid: rec["SPECOBJID"],
    firefly_plate: rec["PLATE"],
    firefly_mjd: rec["MJD"],
    firefly_fiberid: rec["FIBERID"],
    firefly_class: rec["CLASS"],
    firefly_subclass: rec["SUBCLASS"],
    firefly_z: float_or_nil(rec["Z"]),
    firefly_z_err: float_or_nil(rec["Z_ERR"]),
    firefly_ra: ra,
    firefly_dec: dec,
    firefly_chabrier_miles_age_massw: float_or_nil(rec["Chabrier_MILES_age_massW"]),
    firefly_chabrier_miles_metallicity_massw: float_or_nil(rec["Chabrier_MILES_metallicity_massW"]),
    firefly_chabrier_miles_stellar_mass: float_or_nil(rec["Chabrier_MILES_stellar_mass"])
  }
end

def bintable_column_offsets(header, needed_names)
  tfields = Integer(header["TFIELDS"] || 0)
  offsets = {}
  cursor = 0
  needed_set = needed_names.each_with_object({}) { |n, h| h[n] = true }

  (1..tfields).each do |i|
    name = header["TTYPE#{i}"]&.to_s
    form = header["TFORM#{i}"]&.to_s
    raise "Missing TFORM/TTYPE for column #{i}" if name.blank? || form.blank?

    bytes = tform_size_bytes(form)
    if needed_set[name]
      offsets[name] = { offset: cursor, form: form }
    end
    cursor += bytes
  end

  missing = needed_names.reject { |n| offsets.key?(n) }
  raise "Missing required FIREFLY columns: #{missing.join(', ')}" if missing.any?

  offsets
end

def tform_size_bytes(form)
  m = form.to_s.strip.upcase.match(/\A(\d*)([A-Z])\z/)
  raise "Unsupported TFORM for size calc: #{form}" unless m

  repeat = m[1].empty? ? 1 : m[1].to_i
  unit =
    case m[2]
    when "A", "B" then 1
    when "I" then 2
    when "J", "E" then 4
    when "K", "D" then 8
    else
      raise "Unsupported TFORM code for size calc: #{m[2]}"
    end
  repeat * unit
end

def decode_row_subset(row_buf, offsets)
  offsets.each_with_object({}) do |(name, spec), h|
    h[name] = decode_tform_scalar(row_buf, spec[:offset], spec[:form])
  end
end

def decode_tform_scalar(buf, offset, form)
  m = form.to_s.strip.upcase.match(/\A(\d*)([A-Z])\z/)
  raise "Unsupported TFORM decode: #{form}" unless m

  repeat = m[1].empty? ? 1 : m[1].to_i
  code = m[2]
  raw = buf.byteslice(offset, tform_size_bytes(form))

  case code
  when "A"
    raw.to_s.strip
  when "B"
    vals = raw.bytes
    repeat == 1 ? vals[0] : vals
  when "I"
    vals = repeat.times.map { |i| raw.byteslice(i * 2, 2).unpack1("s>") }
    repeat == 1 ? vals[0] : vals
  when "J"
    vals = repeat.times.map { |i| raw.byteslice(i * 4, 4).unpack1("l>") }
    repeat == 1 ? vals[0] : vals
  when "K"
    vals = repeat.times.map { |i| raw.byteslice(i * 8, 8).unpack1("q>") }
    repeat == 1 ? vals[0] : vals
  when "E"
    vals = repeat.times.map { |i| raw.byteslice(i * 4, 4).unpack1("g") }
    repeat == 1 ? vals[0] : vals
  when "D"
    vals = repeat.times.map { |i| raw.byteslice(i * 8, 8).unpack1("G") }
    repeat == 1 ? vals[0] : vals
  else
    raise "Unsupported TFORM code decode: #{code}"
  end
end

def compare_eboss_match_with_observations(match)
  zsun = 0.02
  galaxy_id = match["galaxy_id"]
  galaxy = Galaxy.find_by(id: galaxy_id)
  observations = Observation.where(galaxy_id: galaxy_id).to_a

  obs_age_vals = observations.map { |o| float_or_nil(o.age_gyr) }.compact
  obs_z_vals = observations.map { |o| float_or_nil(o.metallicity_z) }.compact
  obs_mass_vals = observations.map { |o| float_or_nil(o.stellar_mass) }.compact.select(&:positive?)

  obs_age_gyr = average_or_nil(obs_age_vals)
  obs_metallicity_z = average_or_nil(obs_z_vals)
  obs_stellar_mass_msun = average_or_nil(obs_mass_vals)

  ff_age_raw = float_or_nil(match["firefly_chabrier_miles_age_massw"])
  ff_age_gyr = normalize_firefly_age_to_gyr(ff_age_raw)
  ff_z_raw = float_or_nil(match["firefly_chabrier_miles_metallicity_massw"])
  ff_z_assuming_linear = ff_z_raw.nil? ? nil : (ff_z_raw * zsun)
  ff_mass = float_or_nil(match["firefly_chabrier_miles_stellar_mass"])

  {
    galaxy_id: galaxy_id,
    galaxy_name: match["galaxy_name"] || galaxy&.name,
    match_type: match["match_type"],
    separation_arcsec: float_or_nil(match["separation_arcsec"]),
    observations_count: observations.size,
    obs_age_gyr: obs_age_gyr,
    obs_metallicity_z: obs_metallicity_z,
    obs_stellar_mass_msun: obs_stellar_mass_msun,
    firefly_age_massw_raw: ff_age_raw,
    firefly_age_gyr: ff_age_gyr,
    firefly_metallicity_massw_raw: ff_z_raw,
    firefly_metallicity_z_assuming_linear_z_over_zsun: ff_z_assuming_linear,
    firefly_metallicity_conversion_note: "Assumes FIREFLY metallicity is linear Z/Zsun and uses Zsun=#{zsun}",
    firefly_stellar_mass_msun: ff_mass,
    delta_age_gyr: (ff_age_gyr && obs_age_gyr) ? (ff_age_gyr - obs_age_gyr) : nil,
    ratio_age: (ff_age_gyr && obs_age_gyr&.positive?) ? (ff_age_gyr / obs_age_gyr) : nil,
    delta_metallicity_z: (ff_z_assuming_linear && obs_metallicity_z) ? (ff_z_assuming_linear - obs_metallicity_z) : nil,
    ratio_metallicity: (ff_z_assuming_linear && obs_metallicity_z&.positive?) ? (ff_z_assuming_linear / obs_metallicity_z) : nil,
    delta_stellar_mass_msun: (ff_mass && obs_stellar_mass_msun) ? (ff_mass - obs_stellar_mass_msun) : nil,
    ratio_stellar_mass: (ff_mass && obs_stellar_mass_msun&.positive?) ? (ff_mass / obs_stellar_mass_msun) : nil
  }
end

def normalize_firefly_age_to_gyr(value)
  return nil if value.nil?
  # DR16 FIREFLY age fields are typically in years (~1e10 for old populations).
  value > 1_000_000.0 ? (value / 1_000_000_000.0) : value
end

def average_or_nil(values)
  return nil if values.empty?

  values.sum / values.size.to_f
end

def normalize_sdss_objid(value)
  s = value.to_s.strip
  return nil if s.empty?

  s
end

def best_row_by_separation(rows, target_ra, target_dec)
  rows
    .map { |row| row.merge(separation_arcsec: angular_separation_arcsec(target_ra, target_dec, row[:ra], row[:dec])) }
    .min_by { |row| row[:separation_arcsec] }
end

def find_best_match_by_radec(rows_by_ra, target_ra, target_dec, tol_arcsec)
  tol_deg = tol_arcsec / 3600.0
  cos_dec = Math.cos(target_dec * Math::PI / 180.0).abs
  cos_dec = 1.0e-6 if cos_dec < 1.0e-6
  ra_window = tol_deg / cos_dec

  left = lower_bound_ra(rows_by_ra, target_ra - ra_window)
  right = upper_bound_ra(rows_by_ra, target_ra + ra_window)
  return nil if left >= right

  best = nil
  (left...right).each do |i|
    row = rows_by_ra[i]
    sep = angular_separation_arcsec(target_ra, target_dec, row[:ra], row[:dec])
    next if sep > tol_arcsec

    if best.nil? || sep < best[:separation_arcsec]
      best = row.merge(separation_arcsec: sep)
    end
  end

  best
end

def mass_rows_at_indices(mass_path, target_indices)
  target_set = target_indices.each_with_object({}) { |idx, h| h[idx] = true }
  rows = {}
  max_index = target_indices.max || -1

  FitsParser.open(mass_path) do |parser|
    hdu = parser.parse_hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" }
    parser.each_bintable_row(hdu).with_index do |row, idx|
      break if idx > max_index
      next unless target_set[idx]

      rows[idx] = row
      break if rows.size == target_indices.size
    end
  end

  rows
end

def compare_pdf_entry_with_observations(entry)
  galaxy_id = entry["galaxy_id"]
  galaxy = Galaxy.find_by(id: galaxy_id)
  observations = Observation.where(galaxy_id: galaxy_id).where.not(stellar_mass: nil).to_a
  observed_masses = observations.map { |o| o.stellar_mass.to_f }.select(&:positive?)
  observed_log_values = observed_masses.map { |m| Math.log10(m) }
  observed_log_mstar = observed_log_values.empty? ? nil : (observed_log_values.sum / observed_log_values.size)

  pdf = entry["pdf_log_mstar"] || {}
  p16 = float_or_nil(pdf["P16"])
  p84 = float_or_nil(pdf["P84"])
  p2p5 = float_or_nil(pdf["P2P5"])
  p97p5 = float_or_nil(pdf["P97P5"])
  median = float_or_nil(pdf["MEDIAN"])
  mode = float_or_nil(pdf["MODE"])
  avg = float_or_nil(pdf["AVG"])

  {
    galaxy_id: galaxy_id,
    name: entry["name"] || galaxy&.name,
    fit_index: entry["fit_index"],
    separation_arcsec: entry["separation_arcsec"],
    observation_count: observations.size,
    observed_stellar_mass_msun_avg: observed_masses.empty? ? nil : (observed_masses.sum / observed_masses.size),
    observed_log_mstar: observed_log_mstar,
    pdf_median_log_mstar: median,
    pdf_mode_log_mstar: mode,
    pdf_avg_log_mstar: avg,
    delta_obs_minus_pdf_median_dex: (observed_log_mstar && median) ? (observed_log_mstar - median) : nil,
    delta_obs_minus_pdf_mode_dex: (observed_log_mstar && mode) ? (observed_log_mstar - mode) : nil,
    delta_obs_minus_pdf_avg_dex: (observed_log_mstar && avg) ? (observed_log_mstar - avg) : nil,
    within_p16_p84: observed_log_mstar && p16 && p84 ? (observed_log_mstar >= p16 && observed_log_mstar <= p84) : nil,
    within_p2p5_p97p5: observed_log_mstar && p2p5 && p97p5 ? (observed_log_mstar >= p2p5 && observed_log_mstar <= p97p5) : nil,
    pdf_log_mstar: pdf
  }
end

def float_or_nil(v)
  return nil if v.nil?

  Float(v)
rescue ArgumentError, TypeError
  nil
end

def lower_bound_ra(rows_by_ra, value)
  lo = 0
  hi = rows_by_ra.length
  while lo < hi
    mid = (lo + hi) / 2
    if rows_by_ra[mid][:ra] < value
      lo = mid + 1
    else
      hi = mid
    end
  end
  lo
end

def upper_bound_ra(rows_by_ra, value)
  lo = 0
  hi = rows_by_ra.length
  while lo < hi
    mid = (lo + hi) / 2
    if rows_by_ra[mid][:ra] <= value
      lo = mid + 1
    else
      hi = mid
    end
  end
  lo
end
