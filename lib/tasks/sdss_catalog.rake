namespace :sdss do
  SPEED_OF_LIGHT_KM_S = 299_792.458
  HUBBLE_CONSTANT_KM_S_MPC = 70.0
  DECELERATION_PARAMETER = -0.55

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

  desc "Backfill galaxies.redshift_z from live SDSS (objid-strict for writes). WRITE=true to persist."
  task backfill_redshifts: :environment do
    config = PipelineConfig.current
    sdss_release = config.sdss_dataset_release
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    radius_arcmin = ENV.fetch("RADIUS_ARCMIN", "2.0").to_f
    max_match_distance_arcmin = ENV.fetch("MAX_MATCH_ARCMIN", "0.5").to_f
    scope = Galaxy.where("redshift_z IS NULL OR redshift_z = 0").order(:id)
    total = scope.count

    if scope.empty?
      puts "No galaxies with missing/zero redshift_z."
      next
    end

    client = StellarPop::SdssClient.new(release: sdss_release)
    updated = 0
    unresolved = 0

    scope.each do |galaxy|
      result = nil
      source = nil

      if galaxy.sdss_objid.present?
        result = client.fetch_redshift_by_objid(galaxy.sdss_objid)
        source = "objid"
      else
        result = client.fetch_redshift(galaxy.ra, galaxy.dec, radius_arcmin: radius_arcmin)
        source = "coords"
      end

      if result.nil?
        nearest = client.fetch_nearest_spec_match(galaxy.ra, galaxy.dec, radius_arcmin: radius_arcmin)
        distance = nearest && nearest[:distance_arcmin].to_f
        if nearest && distance.finite? && distance <= max_match_distance_arcmin
          result = nearest
          source = "nearest_spec"
        elsif nearest
          puts "#{galaxy.name}: nearest_spec rejected distance=#{format('%.4f', distance)} arcmin"
        end
      end

      z = result && result[:redshift_z].to_f
      if result && z.finite? && !z.zero?
        if write_enabled && source != "objid"
          unresolved += 1
          puts "#{galaxy.name}: skipped write (non-objid source=#{source})"
          sleep(0.3)
          next
        end

        if write_enabled
          attrs = {
            redshift_z: z,
            z_err: result[:redshift_err],
            z_warning: result[:redshift_warning],
            redshift_source: "specobj_bestobjid",
            redshift_confidence: "high",
            redshift_checked_at: Time.current,
            sdss_dr: sdss_release
          }
          objid = result[:objid].to_s.strip
          attrs[:sdss_objid] = objid if objid.match?(/\A[1-9]\d*\z/) && galaxy.sdss_objid.blank?
          upsert_spectroscopy_for_galaxy!(galaxy, {
            redshift_z: attrs[:redshift_z],
            z_err: attrs[:z_err],
            z_warning: attrs[:z_warning],
            redshift_source: attrs[:redshift_source],
            redshift_confidence: attrs[:redshift_confidence],
            redshift_checked_at: attrs[:redshift_checked_at],
            sdss_dr: attrs[:sdss_dr]
          })
          galaxy.update!(attrs)
        end
        updated += 1
        puts "#{galaxy.name}: z=#{format('%.6f', z)} via #{source}"
      else
        unresolved += 1
        puts "#{galaxy.name}: unresolved (reason=#{client.last_failure_reason || 'no_redshift'})"
      end

      sleep(0.3)
    end

    puts "Backfill summary: total=#{total}, updated=#{updated}, unresolved=#{unresolved}, write=#{write_enabled}"
  end

  desc "Fetch DR19 photometry for DR19 galaxies and store petro/model magnitudes"
  task fetch_dr19_photometry: :environment do
    config = PipelineConfig.current
    active_mag_type = config.mag_type
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
        selected_u = active_mag_type == "model" ? result[:model_u] : result[:petro_u]
        selected_g = active_mag_type == "model" ? result[:model_g] : result[:petro_g]
        selected_r = active_mag_type == "model" ? result[:model_r] : result[:petro_r]
        selected_i = active_mag_type == "model" ? result[:model_i] : result[:petro_i]
        selected_z = active_mag_type == "model" ? result[:model_z] : result[:petro_z]
        selected_err_u = active_mag_type == "model" ? result[:model_err_u] : result[:petro_err_u]
        selected_err_g = active_mag_type == "model" ? result[:model_err_g] : result[:petro_err_g]
        selected_err_r = active_mag_type == "model" ? result[:model_err_r] : result[:petro_err_r]
        selected_err_i = active_mag_type == "model" ? result[:model_err_i] : result[:petro_err_i]
        selected_err_z = active_mag_type == "model" ? result[:model_err_z] : result[:petro_err_z]

        photometry_attrs = {
          petro_u: result[:petro_u],
          petro_g: result[:petro_g],
          petro_r: result[:petro_r],
          petro_i: result[:petro_i],
          petro_z: result[:petro_z],
          petro_err_u: result[:petro_err_u],
          petro_err_g: result[:petro_err_g],
          petro_err_r: result[:petro_err_r],
          petro_err_i: result[:petro_err_i],
          petro_err_z: result[:petro_err_z],
          model_u: result[:model_u],
          model_g: result[:model_g],
          model_r: result[:model_r],
          model_i: result[:model_i],
          model_z: result[:model_z],
          model_err_u: result[:model_err_u],
          model_err_g: result[:model_err_g],
          model_err_r: result[:model_err_r],
          model_err_i: result[:model_err_i],
          model_err_z: result[:model_err_z],
          mag_u: selected_u,
          mag_g: selected_g,
          mag_r: selected_r,
          mag_i: selected_i,
          mag_z: selected_z,
          err_u: selected_err_u,
          err_g: selected_err_g,
          err_r: selected_err_r,
          err_i: selected_err_i,
          err_z: selected_err_z,
          extinction_u: result[:extinction_u],
          extinction_g: result[:extinction_g],
          extinction_r: result[:extinction_r],
          extinction_i: result[:extinction_i],
          extinction_z: result[:extinction_z],
          sdss_clean: result[:sdss_clean],
          id_match_quality: (fetch_path == "objid" ? "exact_objid" : "coord_validated"),
          id_match_distance_arcsec: (fetch_path == "objid" ? 0.0 : nil),
          id_match_note: "DR19 photometry fetch via #{fetch_path}",
          mag_type: active_mag_type,
          sdss_dr: "DR19"
        }

        existing_spec = galaxy.galaxy_spectroscopy
        spectroscopy_attrs = {
          redshift_z: result[:redshift_z] || existing_spec&.redshift_z || galaxy.redshift_z,
          z_err: result[:z_err],
          z_warning: result[:z_warning],
          redshift_source: existing_spec&.redshift_source || galaxy.redshift_source,
          redshift_confidence: existing_spec&.redshift_confidence || galaxy.redshift_confidence,
          redshift_checked_at: existing_spec&.redshift_checked_at || galaxy.redshift_checked_at,
          sdss_dr: "DR19"
        }

        upsert_photometry_for_galaxy!(galaxy, photometry_attrs)
        upsert_spectroscopy_for_galaxy!(galaxy, spectroscopy_attrs)
        galaxy.update!(photometry_attrs.merge(
          redshift_z: spectroscopy_attrs[:redshift_z],
          z_err: spectroscopy_attrs[:z_err],
          z_warning: spectroscopy_attrs[:z_warning]
        ))
        puts "#{galaxy.name}: success via #{fetch_path} petro_r=#{result[:petro_r].inspect}"
      else
        puts "#{galaxy.name}: failure via #{fetch_path} reason=#{failure_reason || client.last_failure_reason || 'unknown'} petro_r=nil"
      end

      sleep(0.5)
    end
  end

  desc "Refresh DR19 spectroscopy quality fields (objid-strict; redshift_z, z_err, z_warning) for DR19 galaxies"
  task refresh_dr19_spectroscopy: :environment do
    galaxies = Galaxy.where(sdss_dr: "DR19").order(:id)
    if galaxies.empty?
      puts "No DR19 galaxies found."
      next
    end

    client = StellarPop::SdssClient.new(release: "DR19")
    updated = 0
    unresolved = 0

    galaxies.each do |galaxy|
      result = nil
      source = "objid"
      if galaxy.sdss_objid.present?
        result = client.fetch_redshift_by_objid(galaxy.sdss_objid)
      end

      z = result && result[:redshift_z].to_f
      if result && z.finite? && !z.zero?
        z_warning = result[:redshift_warning]
        confidence = (z_warning.to_i == 0) ? "high" : "medium"
        spectroscopy_attrs = {
          redshift_z: z,
          z_err: result[:redshift_err],
          z_warning: z_warning,
          redshift_source: "specobj_bestobjid",
          redshift_confidence: confidence,
          redshift_checked_at: Time.current,
          sdss_dr: "DR19"
        }
        upsert_spectroscopy_for_galaxy!(galaxy, spectroscopy_attrs)
        galaxy.update!(spectroscopy_attrs)
        updated += 1
        puts "#{galaxy.name}: z=#{format('%.6f', z)} z_err=#{result[:redshift_err].inspect} z_warning=#{result[:redshift_warning].inspect} via #{source}"
      else
        spectroscopy_attrs = {
          z_err: nil,
          z_warning: nil,
          redshift_source: "unresolved",
          redshift_confidence: "low",
          redshift_checked_at: Time.current,
          sdss_dr: "DR19"
        }
        upsert_spectroscopy_for_galaxy!(galaxy, spectroscopy_attrs)
        galaxy.update!(spectroscopy_attrs.except(:sdss_dr))
        unresolved += 1
        puts "#{galaxy.name}: unresolved (objid=#{galaxy.sdss_objid.presence || 'nil'} reason=#{client.last_failure_reason || 'no_redshift'})"
      end

      sleep(0.2)
    end

    puts "Spectroscopy refresh summary: total=#{galaxies.count}, updated=#{updated}, unresolved=#{unresolved}"
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
      stored_validated_objid = nil
      if correct_objid.present?
        validated_objid, _photometry, _reason = validated_objid_fetch(client, correct_objid)
      end
      if stored_objid.present?
        stored_validated_objid, _stored_photometry, _stored_reason = validated_objid_fetch(client, stored_objid)
      end

      # Avoid false positives for large/extended galaxies where nearest type=3 search
      # returns no candidate inside the radius but the stored ObjID is still valid.
      if validated_objid.nil? && stored_validated_objid == stored_objid
        puts "#{galaxy.name}: unverifiable_within_radius stored_valid=#{stored_objid}"
      elsif validated_objid != stored_objid
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

  desc "Compute redshift-based luminosity distance for galaxies (Mpc + light-years). WRITE=true to persist."
  task compute_redshift_distances: :environment do
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("WRITE", "true"))
    max_z = ENV["MAX_Z"].present? ? ENV["MAX_Z"].to_f : nil
    scope = Galaxy.where.not(redshift_z: nil).where("redshift_z > 0").order(:id)
    scope = scope.where("redshift_z <= ?", max_z) if max_z

    total = scope.count
    if total.zero?
      puts "No galaxies with positive redshift_z found."
      next
    end

    updated = 0
    skipped = 0

    scope.find_each(batch_size: 500) do |galaxy|
      z = galaxy.redshift_z.to_f
      d_mpc = approximate_luminosity_distance_mpc(z)
      d_ly = mpc_to_light_years(d_mpc)

      if d_mpc.nil? || d_ly.nil? || !d_mpc.finite? || !d_ly.finite? || d_mpc <= 0 || d_ly <= 0
        skipped += 1
        next
      end

      if write_enabled
        galaxy.update!(
          luminosity_distance_mpc: d_mpc,
          luminosity_distance_ly: d_ly,
          distance_calc_method: "hubble_q0_approx",
          distance_updated_at: Time.current
        )
      end

      updated += 1
    end

    puts "Distance calculation summary:"
    puts "  galaxies considered: #{total}"
    puts "  distances computed: #{updated}"
    puts "  skipped: #{skipped}"
    puts "  write mode: #{write_enabled}"
    puts "  method: D_L ~= (c/H0)*z*(1 + 0.5*(1-q0)*z), H0=#{HUBBLE_CONSTANT_KM_S_MPC}, q0=#{DECELERATION_PARAMETER}"
  end

  desc "Report galaxy distances in million light-years (Mly) and Mpc"
  task report_distances: :environment do
    scope = Galaxy.where.not(luminosity_distance_mpc: nil).where.not(luminosity_distance_ly: nil).order(:id)
    if scope.none?
      puts "No galaxies with computed distances found. Run: bin/rails sdss:compute_redshift_distances"
      next
    end

    puts "Galaxy distance report"
    puts "name | redshift_z | distance_mpc | distance_mly"

    scope.find_each(batch_size: 500) do |galaxy|
      mpc = galaxy.luminosity_distance_mpc.to_f
      mly = galaxy.luminosity_distance_ly.to_f / 1_000_000.0
      puts "#{galaxy.name} | #{format('%.6f', galaxy.redshift_z.to_f)} | #{format('%.3f', mpc)} | #{format('%.3f', mly)}"
    end

    puts "total rows: #{scope.count}"
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

  def approximate_luminosity_distance_mpc(redshift_z)
    z = redshift_z.to_f
    return nil unless z.positive?

    linear_mpc = (SPEED_OF_LIGHT_KM_S / HUBBLE_CONSTANT_KM_S_MPC) * z
    correction = 1.0 + (0.5 * (1.0 - DECELERATION_PARAMETER) * z)
    linear_mpc * correction
  end

  def mpc_to_light_years(distance_mpc)
    return nil if distance_mpc.nil?

    distance_mpc.to_f * 3_261_560.0
  end

  def upsert_photometry_for_galaxy!(galaxy, attrs)
    rec = GalaxyPhotometry.find_or_initialize_by(galaxy_id: galaxy.id)
    rec.update!(attrs)
  end

  def upsert_spectroscopy_for_galaxy!(galaxy, attrs)
    rec = GalaxySpectroscopy.find_or_initialize_by(galaxy_id: galaxy.id)
    rec.update!(attrs)
  end

end
