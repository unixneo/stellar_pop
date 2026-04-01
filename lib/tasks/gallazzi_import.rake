# frozen_string_literal: true

require "open-uri"
require "fits_parser"
require "json"

namespace :gallazzi do
  METALLICITY_URL = "https://wwwmpa.mpa-garching.mpg.de/SDSS/DR2/Data/gallazzi_z_star.txt"
  AGE_URL = "https://wwwmpa.mpa-garching.mpg.de/SDSS/DR2/Data/gallazzi_lwage.txt"
  BATCH_SIZE = 2_000

  desc "Import DR2 Gallazzi stellar metallicity and r-band weighted age catalogs"
  task import_dr2: :environment do
    ensure_external_tables!
    imported_metals = import_metallicities
    imported_ages = import_ages

    puts "Imported/updated metallicity rows: #{imported_metals}"
    puts "Imported/updated age rows: #{imported_ages}"
  end

  desc "Resolve RA/DEC for Gallazzi age rows and compare with main galaxies: bin/rails 'gallazzi:compare_ages_to_galaxies[1,/tmp/report.json,0]'"
  task :compare_ages_to_galaxies, [:tol_arcsec, :out, :limit] => :environment do |_task, args|
    tol_arcsec = Float(args[:tol_arcsec].presence || ENV["TOL_ARCSEC"] || 1.0)
    out = args[:out].presence || ENV["FIT_OUT"] || Rails.root.join("lib/data/fit/gallazzi_age_vs_main_galaxies.json").to_s
    limit = Integer(args[:limit].presence || ENV["LIMIT"] || 0)

    gal_info_path = Rails.root.join("lib/data/fit/gal_info_dr7_v5_2.fit").to_s
    abort "Missing FIT file: #{gal_info_path}" unless File.file?(gal_info_path)

    puts "Loading gal_info (plate,mjd,fiber -> RA/DEC/PHOTOID) index..."
    gal_info = load_gal_info_coords_by_key(gal_info_path)
    gal_info_index = gal_info[:by_key]
    puts "gal_info indexed rows: #{gal_info_index.size}"

    galaxies = Galaxy.where.not(ra: nil, dec: nil).select(:id, :name, :ra, :dec, :sdss_objid).to_a
    abort "No galaxies with RA/DEC found in main DB" if galaxies.empty?
    puts "Main DB galaxies with coordinates: #{galaxies.size}"
    galaxies_by_objid = galaxies.group_by { |g| normalize_sdss_objid(g.sdss_objid) }.except(nil)

    comparisons = []
    total_age_rows = 0
    resolved_coords = 0
    unresolved_coords = 0
    matched = 0
    unmatched = 0
    matched_by_objid = 0
    matched_by_radec = 0

    scope = GallazziRbandWeightedAge.order(:id)
    scope = scope.limit(limit) if limit.positive?

    scope.find_each(batch_size: 5_000) do |age_row|
      total_age_rows += 1
      key = [age_row.plateid.to_i, age_row.mjd.to_i, age_row.fiberid.to_i]
      coords = gal_info_index[key]

      unless coords
        unresolved_coords += 1
        next
      end
      resolved_coords += 1

      best = nil
      match_type = nil

      if coords[:photoid].present?
        objid_candidates = galaxies_by_objid[coords[:photoid]]
        if objid_candidates.present?
          best = best_objid_match(objid_candidates, coords[:ra], coords[:dec])
          match_type = "sdss_objid" if best
        end
      end

      unless best
        best = nearest_galaxy_match(galaxies, coords[:ra], coords[:dec], tol_arcsec)
        match_type = "radec" if best
      end

      if best
        matched += 1
        matched_by_objid += 1 if match_type == "sdss_objid"
        matched_by_radec += 1 if match_type == "radec"
        comparisons << {
          gallazzi_age_id: age_row.id,
          plateid: age_row.plateid,
          mjd: age_row.mjd,
          fiberid: age_row.fiberid,
          gallazzi_photoid: coords[:photoid],
          gallazzi_ra: coords[:ra],
          gallazzi_dec: coords[:dec],
          galaxy_id: best[:galaxy].id,
          galaxy_name: best[:galaxy].name,
          galaxy_ra: best[:galaxy].ra,
          galaxy_dec: best[:galaxy].dec,
          match_type: match_type,
          separation_arcsec: best[:separation_arcsec],
          sdss_objid: best[:galaxy].sdss_objid,
          median_log_yr: age_row.median_log_yr,
          p16_log_yr: age_row.p16_log_yr,
          p84_log_yr: age_row.p84_log_yr,
          mode_log_yr: age_row.mode_log_yr
        }
      else
        unmatched += 1
      end
    end

    payload = {
      source: {
        gallazzi_age_rows_scanned: total_age_rows,
        gallazzi_age_limit: limit.positive? ? limit : nil,
        gal_info_fit: gal_info_path
      },
      tolerance_arcsec: tol_arcsec,
      galaxies_in_main_db: galaxies.size,
      resolved_coords: resolved_coords,
      unresolved_coords: unresolved_coords,
      matched: matched,
      matched_by_objid: matched_by_objid,
      matched_by_radec: matched_by_radec,
      unmatched: unmatched,
      matches: comparisons
    }

    File.write(out, JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload.except(:matches))
    puts "Sample matches:"
    comparisons.first(10).each { |m| puts "  - #{m.inspect}" }
    puts "Wrote report: #{out}"
  rescue ArgumentError => e
    abort <<~USAGE
      #{e.class}: #{e.message}
      Usage:
        bin/rails "gallazzi:compare_ages_to_galaxies[1,/tmp/report.json,0]"
      Or:
        TOL_ARCSEC=1 FIT_OUT=/tmp/report.json LIMIT=0 bin/rails gallazzi:compare_ages_to_galaxies
    USAGE
  end

  def ensure_external_tables!
    ensure_metal_table!
    ensure_age_table!
  end

  def ensure_metal_table!
    conn = GallazziStellarMetallicity.connection
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS gallazzi_stellar_metallicities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plateid INTEGER NOT NULL,
        mjd INTEGER NOT NULL,
        fiberid INTEGER NOT NULL,
        p2p5 REAL NOT NULL,
        p16 REAL NOT NULL,
        median_log_z REAL NOT NULL,
        p84 REAL NOT NULL,
        p97p5 REAL NOT NULL,
        mode_log_z REAL NOT NULL,
        sdss_index INTEGER,
        source_release VARCHAR NOT NULL DEFAULT 'DR2',
        source_file VARCHAR NOT NULL DEFAULT 'gallazzi_z_star.txt',
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    SQL
    conn.execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_gallazzi_metals_plate_mjd_fiber
      ON gallazzi_stellar_metallicities (plateid, mjd, fiberid)
    SQL
  end

  def ensure_age_table!
    conn = GallazziRbandWeightedAge.connection
    conn.execute <<~SQL
      CREATE TABLE IF NOT EXISTS gallazzi_rband_weighted_ages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plateid INTEGER NOT NULL,
        mjd INTEGER NOT NULL,
        fiberid INTEGER NOT NULL,
        p2p5_log_yr REAL NOT NULL,
        p16_log_yr REAL NOT NULL,
        median_log_yr REAL NOT NULL,
        p84_log_yr REAL NOT NULL,
        p97p5_log_yr REAL NOT NULL,
        mode_log_yr REAL NOT NULL,
        sdss_index INTEGER,
        source_release VARCHAR NOT NULL DEFAULT 'DR2',
        source_file VARCHAR NOT NULL DEFAULT 'gallazzi_lwage.txt',
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
      )
    SQL
    conn.execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS idx_gallazzi_ages_plate_mjd_fiber
      ON gallazzi_rband_weighted_ages (plateid, mjd, fiberid)
    SQL
  end

  def import_metallicities
    import_generic(
      url: METALLICITY_URL,
      table: GallazziStellarMetallicity,
      source_file: "gallazzi_z_star.txt"
    ) do |parts, now, source_file|
      {
        plateid: parts[0].to_i,
        mjd: parts[1].to_i,
        fiberid: parts[2].to_i,
        p2p5: parts[3].to_f,
        p16: parts[4].to_f,
        median_log_z: parts[5].to_f,
        p84: parts[6].to_f,
        p97p5: parts[7].to_f,
        mode_log_z: parts[8].to_f,
        sdss_index: parts[9]&.to_i,
        source_release: "DR2",
        source_file: source_file,
        created_at: now,
        updated_at: now
      }
    end
  end

  def import_ages
    import_generic(
      url: AGE_URL,
      table: GallazziRbandWeightedAge,
      source_file: "gallazzi_lwage.txt"
    ) do |parts, now, source_file|
      {
        plateid: parts[0].to_i,
        mjd: parts[1].to_i,
        fiberid: parts[2].to_i,
        p2p5_log_yr: parts[3].to_f,
        p16_log_yr: parts[4].to_f,
        median_log_yr: parts[5].to_f,
        p84_log_yr: parts[6].to_f,
        p97p5_log_yr: parts[7].to_f,
        mode_log_yr: parts[8].to_f,
        sdss_index: parts[9]&.to_i,
        source_release: "DR2",
        source_file: source_file,
        created_at: now,
        updated_at: now
      }
    end
  end

  def import_generic(url:, table:, source_file:)
    count = 0
    batch = []
    now = Time.current

    URI.open(url) do |io|
      io.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        parts = line.split
        next if parts.size < 9

        batch << yield(parts, now, source_file)

        if batch.size >= BATCH_SIZE
          table.upsert_all(batch, unique_by: %i[plateid mjd fiberid])
          count += batch.size
          batch.clear
        end
      end
    end

    unless batch.empty?
      table.upsert_all(batch, unique_by: %i[plateid mjd fiberid])
      count += batch.size
    end

    count
  end

  def load_gal_info_coords_by_key(path)
    by_key = {}
    FitsParser.open(path) do |parser|
      hdu = parser.parse_hdus.find { |h| h[:header]["XTENSION"] == "BINTABLE" }
      parser.each_bintable_row(hdu) do |row|
        key = [row["PLATEID"].to_i, row["MJD"].to_i, row["FIBERID"].to_i]
        by_key[key] = {
          ra: row["RA"].to_f,
          dec: row["DEC"].to_f,
          photoid: normalize_sdss_objid(row["PHOTOID"])
        }
      end
    end
    { by_key: by_key }
  end

  def normalize_sdss_objid(value)
    s = value.to_s.strip
    return nil if s.empty?

    s
  end

  def nearest_galaxy_match(galaxies, ra, dec, tol_arcsec)
    best = nil
    galaxies.each do |g|
      sep = angular_sep_arcsec(ra, dec, g.ra.to_f, g.dec.to_f)
      next if sep > tol_arcsec
      next if best && sep >= best[:separation_arcsec]

      best = { galaxy: g, separation_arcsec: sep }
    end
    best
  end

  def best_objid_match(galaxies, ra, dec)
    galaxies
      .map { |g| { galaxy: g, separation_arcsec: angular_sep_arcsec(ra, dec, g.ra.to_f, g.dec.to_f) } }
      .min_by { |m| m[:separation_arcsec] }
  end

  def angular_sep_arcsec(ra1_deg, dec1_deg, ra2_deg, dec2_deg)
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
end
