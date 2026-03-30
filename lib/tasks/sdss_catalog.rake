namespace :sdss do
  desc "Verify Galaxy photometry against SDSS DR18 (WRITE=true to update galaxies.sdss_dr)"
  task verify_photometry: :environment do
    bands = %w[u g r i z].freeze
    tolerance = 0.01
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])

    galaxies = Galaxy.order(:id).to_a
    if galaxies.empty?
      puts "No galaxies found in DB."
      next
    end

    client = StellarPop::SdssClient.new

    verified_count = 0
    unverified_count = 0
    discrepancy_count = 0
    significant_differences = []

    galaxies.each do |galaxy|
      name = galaxy.name.to_s
      ra = galaxy.ra.to_f
      dec = galaxy.dec.to_f

      fetched = client.fetch_photometry(ra, dec)
      if fetched.nil?
        unverified_count += 1
        next
      end

      differences = {}
      bands.each do |band|
        stored_raw = galaxy.public_send("mag_#{band}")
        fetched_raw = fetched[band.to_sym]
        next if stored_raw.nil? || fetched_raw.nil?

        stored_value = stored_raw.to_f
        fetched_value = fetched_raw.to_f
        delta = (fetched_value - stored_value).abs
        differences[band] = delta if delta > tolerance
      end

      if differences.empty?
        verified_count += 1
        galaxy.update!(sdss_dr: "DR18") if write_enabled
      else
        discrepancy_count += 1
        significant_differences << {
          galaxy_id: galaxy.id,
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
        puts "  ##{entry[:galaxy_id]} #{entry[:name]} (ra=#{entry[:ra]}, dec=#{entry[:dec]}): #{diffs}"
      end
    end

    if write_enabled
      puts "Updated galaxies.sdss_dr for verified rows."
    else
      puts "Dry run only (set WRITE=true to persist updates)."
    end
  end
end
