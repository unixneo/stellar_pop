# frozen_string_literal: true

require "fits_parser"
require "json"
require "csv"

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
  dec_rad = dec1_deg * Math::PI / 180.0
  dra = (ra1_deg - ra2_deg) * Math.cos(dec_rad)
  ddec = dec1_deg - dec2_deg
  Math.sqrt((dra * dra) + (ddec * ddec)) * 3600.0
end
