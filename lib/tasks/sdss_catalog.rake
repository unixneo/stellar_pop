namespace :sdss do
  desc "Verify Galaxy photometry against configured SDSS release and infer magnitude type (WRITE=true to update galaxies.sdss_dr and galaxies.mag_type)"
  task verify_photometry: :environment do
    bands = %w[u g r i z].freeze
    tolerance = 0.01
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    config = PipelineConfig.current

    galaxies = Galaxy.order(:id).to_a
    if galaxies.empty?
      puts "No galaxies found in DB."
      next
    end

    sdss_release = config.sdss_dataset_release
    client = StellarPop::SdssClient.new(release: sdss_release)

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
        attrs = { sdss_dr: sdss_release, mag_type: detected_type }
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

  desc "Fetch DR19 photometry for DR19 galaxies and store petro/model magnitudes"
  task fetch_dr19_photometry: :environment do
    galaxies = Galaxy.where(sdss_dr: "DR19").order(:id)
    if galaxies.empty?
      puts "No DR19 galaxies found."
      next
    end

    galaxies.each do |galaxy|
      client = StellarPop::SdssClient.new(release: "DR19")
      result = nil
      fetch_path = "coordinates"
      failure_reason = nil

      if galaxy.sdss_objid.present?
        fetch_path = "objid"
        _validated_objid, result, failure_reason = validated_objid_fetch(client, galaxy.sdss_objid)
      end

      if result.nil?
        fetch_path = "coordinates"
        result = client.fetch_photometry(galaxy.ra, galaxy.dec)
        failure_reason ||= client.last_failure_reason
      end

      if result
        galaxy.update!(
          petro_u: result[:petro_u],
          petro_g: result[:petro_g],
          petro_r: result[:petro_r],
          petro_i: result[:petro_i],
          petro_z: result[:petro_z],
          model_u: result[:model_u],
          model_g: result[:model_g],
          model_r: result[:model_r],
          model_i: result[:model_i],
          model_z: result[:model_z],
          mag_u: result[:petro_u],
          mag_g: result[:petro_g],
          mag_r: result[:petro_r],
          mag_i: result[:petro_i],
          mag_z: result[:petro_z],
          mag_type: "petrosian",
          sdss_dr: "DR19"
        )
        puts "#{galaxy.name}: success via #{fetch_path} petro_r=#{result[:petro_r].inspect}"
      else
        puts "#{galaxy.name}: failure via #{fetch_path} reason=#{failure_reason || client.last_failure_reason || 'unknown'} petro_r=nil"
      end

      sleep(0.5)
    end
  end

  desc "Verify stored DR19 galaxy objids against nearest large type=3 SDSS DR19 match (report only)"
  task verify_objids: :environment do
    galaxies = Galaxy.where(sdss_dr: "DR19").order(:id)
    if galaxies.empty?
      puts "No DR19 galaxies found."
      next
    end

    connection = Faraday.new(
      url: StellarPop::SdssClient.api_url_for("DR19"),
      request: {
        timeout: StellarPop::SdssClient::TIMEOUT_SECONDS,
        open_timeout: StellarPop::SdssClient::TIMEOUT_SECONDS
      }
    )

    galaxies.each do |galaxy|
      sql = <<~SQL
        SELECT TOP 1 p.objid
        FROM PhotoObj AS p
        JOIN fGetNearbyObjEq(#{galaxy.ra.to_f}, #{galaxy.dec.to_f}, 2.0) AS n
          ON n.objid = p.objid
        WHERE p.type = 3
        ORDER BY p.petroMag_r ASC
      SQL
        .gsub(/\s+/, " ")
        .strip

      response = connection.get(nil, cmd: sql, format: "json")
      payload = JSON.parse(response.body.to_s)
      correct_objid = sdss_first_objid_from_payload(payload)
      stored_objid = galaxy.sdss_objid.to_s.presence

      client = StellarPop::SdssClient.new(release: "DR19")
      validated_objid = nil
      if correct_objid.present?
        validated_objid, _photometry, _reason = validated_objid_fetch(client, correct_objid)
      end

      if validated_objid != stored_objid
        puts "#{galaxy.name}: stored=#{stored_objid || 'nil'} correct=#{validated_objid || 'nil'}"
      end
    rescue StandardError => e
      puts "#{galaxy.name}: lookup_failed #{e.class}: #{e.message}"
    end
  end

  desc "Fix DR19 galaxy sdss_objid values using nearest large type=3 SDSS DR19 match"
  task fix_objids: :environment do
    galaxies = Galaxy.where(sdss_dr: "DR19").order(:id)
    if galaxies.empty?
      puts "No DR19 galaxies found."
      next
    end

    connection = Faraday.new(
      url: StellarPop::SdssClient.api_url_for("DR19"),
      request: {
        timeout: StellarPop::SdssClient::TIMEOUT_SECONDS,
        open_timeout: StellarPop::SdssClient::TIMEOUT_SECONDS
      }
    )

    galaxies.each do |galaxy|
      sql = <<~SQL
        SELECT TOP 1 p.objid
        FROM PhotoObj AS p
        JOIN fGetNearbyObjEq(#{galaxy.ra.to_f}, #{galaxy.dec.to_f}, 2.0) AS n
          ON n.objid = p.objid
        WHERE p.type = 3
        ORDER BY p.petroMag_r ASC
      SQL
        .gsub(/\s+/, " ")
        .strip

      response = connection.get(nil, cmd: sql, format: "json")
      payload = JSON.parse(response.body.to_s)
      correct_objid = sdss_first_objid_from_payload(payload)
      old_objid = galaxy.sdss_objid.to_s.presence

      client = StellarPop::SdssClient.new(release: "DR19")
      validated_objid = nil
      failure_reason = nil
      if correct_objid.present?
        validated_objid, _photometry, failure_reason = validated_objid_fetch(client, correct_objid)
      end

      if validated_objid.present?
        galaxy.update!(sdss_objid: validated_objid)
      end

      puts "#{galaxy.name}: old_objid=#{old_objid || 'nil'} new_objid=#{validated_objid || 'nil'}#{validated_objid.nil? ? " reason=#{failure_reason || 'validation_failed'}" : ""}"
    rescue StandardError => e
      puts "#{galaxy.name}: fix_failed #{e.class}: #{e.message}"
    ensure
      sleep(0.3)
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

  def sdss_first_objid_from_payload(payload)
    table =
      if payload.is_a?(Array)
        payload.find { |entry| entry.is_a?(Hash) && (entry["TableName"] || entry[:TableName]).to_s == "Table1" }
      elsif payload.is_a?(Hash)
        payload
      end
    return nil unless table.is_a?(Hash)

    rows = table["Rows"] || table[:Rows] || table["rows"] || table[:rows]
    row = rows.is_a?(Array) ? rows.first : nil
    return nil unless row.is_a?(Hash)

    (row["objid"] || row[:objid]).to_s.presence
  end

  def validated_objid_fetch(client, objid)
    normalized_objid = objid.to_s.strip
    return [nil, nil, :invalid_objid] if normalized_objid.empty?
    return [nil, nil, :invalid_objid] unless normalized_objid.match?(/\A\d+\z/)

    photometry = client.fetch_photometry_by_objid(normalized_objid)
    return [normalized_objid, photometry, nil] if photometry

    [nil, nil, (client.last_failure_reason || :objid_fetch_failed)]
  end

end
