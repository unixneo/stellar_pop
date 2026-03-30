namespace :sdss do
  desc "Verify Galaxy photometry against SDSS DR18 and infer magnitude type (WRITE=true to update galaxies.sdss_dr and galaxies.mag_type)"
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
    petrosian_match_count = 0
    model_match_count = 0
    unknown_match_count = 0
    significant_differences = []

    galaxies.each do |galaxy|
      name = galaxy.name.to_s
      ra = galaxy.ra.to_f
      dec = galaxy.dec.to_f

      profiles = client.fetch_photometry_profiles(ra, dec)
      if profiles.nil?
        unverified_count += 1
        next
      end

      detected_type, fetched = detect_best_profile(galaxy, profiles, bands)
      case detected_type
      when "petrosian"
        petrosian_match_count += 1
      when "model"
        model_match_count += 1
      else
        unknown_match_count += 1
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

      if write_enabled
        attrs = { sdss_dr: "DR18", mag_type: detected_type }
        galaxy.update!(attrs)
      end
    end

    puts "SDSS Photometry Verification Summary"
    puts "  verified count: #{verified_count}"
    puts "  unverified count: #{unverified_count}"
    puts "  discrepancy count: #{discrepancy_count}"
    puts "  inferred mag_type counts: petrosian=#{petrosian_match_count}, model=#{model_match_count}, unknown=#{unknown_match_count}"

    if significant_differences.any?
      puts "Significant differences (>#{tolerance} mag):"
      significant_differences.each do |entry|
        diffs = entry[:differences].map { |band, delta| "#{band}=#{format('%.5f', delta)}" }.join(", ")
        puts "  ##{entry[:galaxy_id]} #{entry[:name]} (ra=#{entry[:ra]}, dec=#{entry[:dec]}): #{diffs}"
      end
    end

    if write_enabled
      puts "Updated galaxies.sdss_dr and galaxies.mag_type for fetched rows."
    else
      puts "Dry run only (set WRITE=true to persist updates)."
    end
  end

  def detect_best_profile(galaxy, profiles, bands)
    petrosian = profiles[:petrosian] || {}
    model = profiles[:model] || {}
    petrosian_score = profile_score(galaxy, petrosian, bands)
    model_score = profile_score(galaxy, model, bands)

    if petrosian_score.finite? && model_score.finite?
      return petrosian_score <= model_score ? ["petrosian", petrosian] : ["model", model]
    end

    if petrosian_score.finite?
      return ["petrosian", petrosian]
    end

    if model_score.finite?
      return ["model", model]
    end

    fallback = choose_non_empty_profile(petrosian, model, bands)
    ["unknown", fallback]
  end

  def profile_score(galaxy, profile, bands)
    deltas = bands.filter_map do |band|
      stored_raw = galaxy.public_send("mag_#{band}")
      fetched_raw = profile[band.to_sym]
      next if stored_raw.nil? || fetched_raw.nil?

      (fetched_raw.to_f - stored_raw.to_f).abs
    end
    return Float::INFINITY if deltas.empty?

    deltas.sum / deltas.length.to_f
  end

  def choose_non_empty_profile(petrosian, model, bands)
    petrosian_count = bands.count { |band| !petrosian[band.to_sym].nil? }
    model_count = bands.count { |band| !model[band.to_sym].nil? }
    petrosian_count >= model_count ? petrosian : model
  end
end
