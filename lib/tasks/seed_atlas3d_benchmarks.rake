namespace :atlas3d do
  desc "Seed curated ATLAS3D benchmark galaxies and observations"
  task seed_benchmarks: :environment do
    galaxies = [
      { name: "NGC4660", ra: 190.9154, dec: 11.1974, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 15.7, angular_size_arcmin: 1.3, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 1 benchmark. Compact E5, fast rotator, clean SDSS photometry." },
      { name: "NGC4564", ra: 188.4388, dec: 11.4394, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 15.7, angular_size_arcmin: 1.9, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 1 benchmark. Compact E6, old population, clean SDSS." },
      { name: "NGC4387", ra: 186.4263, dec: 12.8107, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 18.0, angular_size_arcmin: 1.4, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 1 benchmark. Compact E5, solar metallicity anchor." },
      { name: "NGC4339", ra: 185.7196, dec: 6.0832, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 16.0, angular_size_arcmin: 1.7, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 2 benchmark. E0, clean, slightly younger population." },
      { name: "NGC4350", ra: 185.9979, dec: 16.6930, sdss_dr: "DR19",
        galaxy_type: "lenticular", distance_mpc: 16.8, angular_size_arcmin: 2.1, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 2 benchmark. S0, clean SDSS photometry." },
      { name: "NGC4452", ra: 187.3871, dec: 11.7561, sdss_dr: "DR19",
        galaxy_type: "lenticular", distance_mpc: 16.0, angular_size_arcmin: 1.6, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 2 benchmark. S0 edge-on, compact, clean." },
      { name: "NGC4474", ra: 187.6263, dec: 14.0692, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 15.5, angular_size_arcmin: 1.8, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 2 benchmark. E/S0, intermediate age, lower-age anchor." },
      { name: "NGC4483", ra: 187.8700, dec: 9.0172, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 16.5, angular_size_arcmin: 1.2, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 2 benchmark. Compact E, lower mass anchor." },
      { name: "NGC4365", ra: 186.1175, dec: 7.3194, sdss_dr: "DR19",
        galaxy_type: "elliptical", distance_mpc: 23.3, angular_size_arcmin: 2.8, agn: false,
        agn_source: "literature_ned", agn_method: "optical_spectroscopy",
        agn_confidence: "high", agn_checked_at: "2026-04-03",
        notes: "ATLAS3D Tier 3 benchmark. Known age outlier >13 Gyr, use with caution." }
    ]

    observations = [
      { galaxy_name: "NGC4660", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 12.5, metallicity_z: 0.030, stellar_mass: 2.24e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.20 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4564", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 12.0, metallicity_z: 0.026, stellar_mass: 2.82e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.10 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4387", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 10.0, metallicity_z: 0.020, stellar_mass: 1.26e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=0.00 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4339", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 9.5, metallicity_z: 0.022, stellar_mass: 1.58e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.05 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4350", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 10.0, metallicity_z: 0.026, stellar_mass: 3.16e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.10 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4452", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 10.5, metallicity_z: 0.022, stellar_mass: 1.41e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.05 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4474", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 8.5, metallicity_z: 0.018, stellar_mass: 1.12e10,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=-0.05 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4483", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 9.0, metallicity_z: 0.020, stellar_mass: 7.94e9,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=0.00 from ATLAS3D SAURON IFU spectroscopy within Re." },
      { galaxy_name: "NGC4365", source_paper: "McDermid et al. 2015, MNRAS 448, 3484",
        age_gyr: 13.5, metallicity_z: 0.032, stellar_mass: 1.58e11,
        method: "ssp_literature",
        notes: "SSP age and [Z/H]=+0.20. Known age outlier >universe age. Tier 3 only." }
    ]

    galaxy_columns = Galaxy.column_names
    observation_columns = Observation.column_names

    galaxies.each do |entry|
      existed_before = Galaxy.where(name: entry[:name]).exists?
      galaxy = Galaxy.find_or_create_by(name: entry[:name])
      existing_record = existed_before
      attrs = {}

      entry.each do |key, value|
        next if key == :name

        col = key.to_s
        if existing_record && %w[ra dec].include?(col)
          puts "[warn] Skipping immutable Galaxy field on existing record: #{col} (#{entry[:name]})"
          next
        end
        if galaxy_columns.include?(col)
          attrs[col] = (col == "agn_checked_at" ? Time.zone.parse(value.to_s) : value)
        else
          puts "[warn] Galaxy column missing: #{col} (#{entry[:name]})"
        end
      end

      galaxy.update!(attrs) if attrs.any?
      puts "[galaxy] #{entry[:name]} updated (agn=#{galaxy.agn}, sdss_dr=#{galaxy.sdss_dr})"
    end

    observations.each do |entry|
      galaxy_name = entry[:galaxy_name].to_s
      galaxy = Galaxy.find_by(name: galaxy_name)
      unless galaxy
        puts "[warn] Galaxy not found for observation: #{galaxy_name}"
        next
      end

      observation = Observation.find_or_create_by(galaxy_id: galaxy.id, source_paper: entry[:source_paper])
      attrs = {}

      attrs["sdss_objid"] = galaxy.sdss_objid if observation_columns.include?("sdss_objid")
      attrs["age_gyr"] = entry[:age_gyr] if observation_columns.include?("age_gyr")
      attrs["metallicity_z"] = entry[:metallicity_z] if observation_columns.include?("metallicity_z")
      attrs["stellar_mass"] = entry[:stellar_mass] if observation_columns.include?("stellar_mass")
      attrs["notes"] = entry[:notes] if observation_columns.include?("notes")
      if observation_columns.include?("method_used")
        attrs["method_used"] = entry[:method]
      elsif observation_columns.include?("method")
        attrs["method"] = entry[:method]
      else
        puts "[warn] Observation method column missing (expected method_used or method)"
      end

      if attrs["sdss_objid"].to_s.strip.empty?
        puts "[warn] Missing sdss_objid for observation: #{galaxy_name} (skipped)"
        next
      end

      observation.update!(attrs)
      puts "[observation] #{galaxy_name} upserted (source=#{entry[:source_paper]})"
    end
  end
end
