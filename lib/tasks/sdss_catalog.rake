require "csv"

namespace :sdss do
  desc "Verify local SDSS catalog photometry against SDSS DR18 (WRITE=true to update sdss_dr)"
  task verify_photometry: :environment do
    csv_path = Rails.root.join("lib/data/sdss/photometry.csv")
    bands = %w[u g r i z].freeze
    tolerance = 0.01
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])

    unless File.exist?(csv_path)
      puts "Catalog not found: #{csv_path}"
      next
    end

    rows = CSV.read(csv_path, headers: true)
    if rows.empty?
      puts "Catalog is empty: #{csv_path}"
      next
    end

    client = StellarPop::SdssClient.new

    verified_count = 0
    unverified_count = 0
    discrepancy_count = 0
    significant_differences = []

    rows.each do |row|
      name = row["name"].to_s
      ra = row["ra"].to_f
      dec = row["dec"].to_f

      fetched = client.fetch_photometry(ra, dec)
      if fetched.nil?
        unverified_count += 1
        next
      end

      differences = {}
      bands.each do |band|
        stored_raw = row[band]
        fetched_raw = fetched[band.to_sym]
        next if stored_raw.nil? || fetched_raw.nil?

        stored_value = stored_raw.to_f
        fetched_value = fetched_raw.to_f
        delta = (fetched_value - stored_value).abs
        differences[band] = delta if delta > tolerance
      end

      if differences.empty?
        verified_count += 1
        row["sdss_dr"] = "DR18"
      else
        discrepancy_count += 1
        significant_differences << {
          name: name,
          ra: ra,
          dec: dec,
          differences: differences
        }
      end
    end

    puts "SDSS Photometry Verification Summary"
    puts "  verified count: #{verified_count}"
    puts "  unverified count: #{unverified_count}"
    puts "  discrepancy count: #{discrepancy_count}"

    if significant_differences.any?
      puts "Significant differences (>#{tolerance} mag):"
      significant_differences.each do |entry|
        diffs = entry[:differences].map { |band, delta| "#{band}=#{format('%.5f', delta)}" }.join(", ")
        puts "  #{entry[:name]} (ra=#{entry[:ra]}, dec=#{entry[:dec]}): #{diffs}"
      end
    end

    if write_enabled
      CSV.open(csv_path, "w") do |csv|
        csv << rows.headers
        rows.each { |row| csv << row.fields }
      end
      puts "Updated catalog written to #{csv_path}"
    else
      puts "Dry run only (set WRITE=true to persist updates)."
    end
  end
end
