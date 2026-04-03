namespace :benchmarks do
  SOLAR_Z = 0.02
  ATLAS3D_SOURCE_PAPER = "McDermid+2015 (SSP), Cappellari+2013 (logM*)".freeze

  # Curated list from literature cross-reference discussion.
  # NOTE:
  # - `ssp_zh` is [Z/H] dex and converted here to absolute Z via Z=Zsun*10^[Z/H], Zsun=0.02.
  # - `log_mstar` is log10(M*/Msun) and converted to stellar mass in Msun.
  CANDIDATES = [
    { name: "NGC4660", ra: 190.9154, dec: 11.1974, distance_mpc: 15.7, angular_size_arcmin: 1.3, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 12.5, ssp_age_err: 1.5, ssp_zh: 0.20, ssp_zh_err: 0.07, log_mstar: 10.35, tier: 1, quality_notes: "Compact E5, fast rotator, excellent SDSS photometry, strong McDermid benchmark" },
    { name: "NGC4564", ra: 188.4388, dec: 11.4394, distance_mpc: 15.7, angular_size_arcmin: 1.9, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 12.0, ssp_age_err: 1.5, ssp_zh: 0.10, ssp_zh_err: 0.07, log_mstar: 10.45, tier: 1, quality_notes: "E6, compact, clean, well-constrained SSP" },
    { name: "NGC4570", ra: 188.6296, dec: 7.2469, distance_mpc: 17.1, angular_size_arcmin: 2.1, galaxy_type: "lenticular", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 11.5, ssp_age_err: 1.5, ssp_zh: 0.15, ssp_zh_err: 0.07, log_mstar: 10.45, tier: 1, quality_notes: "S0, already in DB, good SDSS, keep" },
    { name: "NGC4387", ra: 186.4263, dec: 12.8107, distance_mpc: 18.0, angular_size_arcmin: 1.4, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 10.0, ssp_age_err: 2.0, ssp_zh: 0.00, ssp_zh_err: 0.08, log_mstar: 10.10, tier: 1, quality_notes: "E5, compact, solar metallicity anchor" },
    { name: "NGC4339", ra: 185.7196, dec: 6.0832, distance_mpc: 16.0, angular_size_arcmin: 1.7, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 9.5, ssp_age_err: 2.0, ssp_zh: 0.05, ssp_zh_err: 0.08, log_mstar: 10.20, tier: 2, quality_notes: "E0, clean, slightly younger population" },
    { name: "NGC4350", ra: 185.9979, dec: 16.6930, distance_mpc: 16.8, angular_size_arcmin: 2.1, galaxy_type: "lenticular", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 10.0, ssp_age_err: 2.0, ssp_zh: 0.10, ssp_zh_err: 0.08, log_mstar: 10.50, tier: 2, quality_notes: "S0, edge-on disk, good SDSS" },
    { name: "NGC4452", ra: 187.3871, dec: 11.7561, distance_mpc: 16.0, angular_size_arcmin: 1.6, galaxy_type: "lenticular", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 10.5, ssp_age_err: 2.0, ssp_zh: 0.05, ssp_zh_err: 0.08, log_mstar: 10.15, tier: 2, quality_notes: "S0 edge-on, compact, clean" },
    { name: "NGC4474", ra: 187.6263, dec: 14.0692, distance_mpc: 15.5, angular_size_arcmin: 1.8, galaxy_type: "lenticular", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 8.5, ssp_age_err: 2.0, ssp_zh: -0.05, ssp_zh_err: 0.09, log_mstar: 10.05, tier: 2, quality_notes: "E/S0, fast rotator, intermediate age" },
    { name: "NGC4483", ra: 187.8700, dec: 9.0172, distance_mpc: 16.5, angular_size_arcmin: 1.2, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 9.0, ssp_age_err: 2.0, ssp_zh: 0.00, ssp_zh_err: 0.09, log_mstar: 9.90, tier: 2, quality_notes: "Compact E, clean, lower-mass anchor" },
    { name: "NGC4270", ra: 184.9404, dec: 5.4625, distance_mpc: 35.0, angular_size_arcmin: 1.5, galaxy_type: "lenticular", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 11.0, ssp_age_err: 2.0, ssp_zh: 0.10, ssp_zh_err: 0.08, log_mstar: 10.55, tier: 2, quality_notes: "S0, slightly beyond 30 Mpc but clean" },
    { name: "NGC4365", ra: 186.1175, dec: 7.3194, distance_mpc: 23.3, angular_size_arcmin: 2.8, galaxy_type: "elliptical", agn: false, agn_source: "literature_ned", agn_method: "optical_spectroscopy", agn_confidence: "high", ssp_age_gyr: 13.5, ssp_age_err: 2.0, ssp_zh: 0.20, ssp_zh_err: 0.08, log_mstar: 11.20, tier: 3, quality_notes: "Known age>universe outlier; use with caution" }
  ].freeze

  desc "Ingest curated ATLAS3D benchmark candidates into galaxies + observations. Dry run by default. Use WRITE=true to persist."
  task ingest_curated_atlas3d: :environment do
    write_enabled = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"])
    sdss_dr = ENV.fetch("SDSS_DR", "DR19")
    now = Time.current

    created_galaxies = 0
    updated_galaxies = 0
    created_observations = 0
    updated_observations = 0
    skipped_observations = 0

    CANDIDATES.each do |entry|
      z_value = SOLAR_Z * (10.0**entry[:ssp_zh].to_f)
      stellar_mass = 10.0**entry[:log_mstar].to_f
      base_notes = "ATLAS3D curated candidate; tier=#{entry[:tier]}; distance_mpc=#{entry[:distance_mpc]}; angular_size_arcmin=#{entry[:angular_size_arcmin]}"
      galaxy_notes = [entry[:quality_notes], base_notes].compact.join(" | ")
      obs_notes = [
        "source_confidence=medium",
        "ssp_age_err_gyr=#{entry[:ssp_age_err]}",
        "ssp_[Z/H]=#{entry[:ssp_zh]}",
        "ssp_[Z/H]_err=#{entry[:ssp_zh_err]}",
        "converted_Z_assumption=Zsun*10^[Z/H],Zsun=#{SOLAR_Z}",
        "tier=#{entry[:tier]}",
        entry[:quality_notes]
      ].join(" | ")

      galaxy = Galaxy.find_or_initialize_by(name: entry[:name])
      new_galaxy = galaxy.new_record?
      galaxy.assign_attributes(
        ra: entry[:ra],
        dec: entry[:dec],
        galaxy_type: entry[:galaxy_type],
        notes: galaxy_notes,
        agn: entry[:agn],
        agn_source: entry[:agn_source],
        agn_method: entry[:agn_method],
        agn_confidence: entry[:agn_confidence],
        agn_checked_at: now,
        sdss_dr: sdss_dr,
        source_catalog: "atlas3d_curated"
      )

      if write_enabled
        galaxy.save!
      end

      if new_galaxy
        created_galaxies += 1
      else
        updated_galaxies += 1
      end

      if galaxy.sdss_objid.to_s.strip.empty?
        skipped_observations += 1
        puts "[skip-observation] #{entry[:name]} has no sdss_objid (requires objid for observations)"
        next
      end

      obs = Observation.find_or_initialize_by(galaxy_id: galaxy.id, source_paper: ATLAS3D_SOURCE_PAPER)
      new_obs = obs.new_record?
      obs.assign_attributes(
        sdss_objid: galaxy.sdss_objid,
        age_gyr: entry[:ssp_age_gyr],
        metallicity_z: z_value,
        stellar_mass: stellar_mass,
        method_used: "atlas3d_ssp_representative",
        notes: obs_notes
      )

      obs.save! if write_enabled
      if new_obs
        created_observations += 1
      else
        updated_observations += 1
      end
    end

    puts({
      write: write_enabled,
      sdss_dr: sdss_dr,
      candidates: CANDIDATES.size,
      galaxies_created: created_galaxies,
      galaxies_updated: updated_galaxies,
      observations_created: created_observations,
      observations_updated: updated_observations,
      observations_skipped_missing_sdss_objid: skipped_observations
    }.inspect)
    puts "Dry run only. Set WRITE=true to persist." unless write_enabled
  end
end
