# frozen_string_literal: true

require "open-uri"

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
end
