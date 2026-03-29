require "csv"

class SeedGalaxiesFromSdssCsv < ActiveRecord::Migration[7.1]
  class MigrationGalaxy < ActiveRecord::Base
    self.table_name = "galaxies"
  end

  def up
    csv_path = Rails.root.join("lib/data/sdss/photometry.csv")
    return unless File.exist?(csv_path)

    now = Time.current
    rows = CSV.read(csv_path, headers: true)
    records = rows.map do |row|
      {
        name: row["name"].to_s.strip,
        ra: to_float_or_nil(row["ra"]),
        dec: to_float_or_nil(row["dec"]),
        mag_u: to_float_or_nil(row["u"]),
        mag_g: to_float_or_nil(row["g"]),
        mag_r: to_float_or_nil(row["r"]),
        mag_i: to_float_or_nil(row["i"]),
        mag_z: to_float_or_nil(row["z"]),
        galaxy_type: blank_to_nil(row["type"]),
        notes: blank_to_nil(row["notes"]),
        agn: parse_boolean(row["agn"]),
        sdss_dr: blank_to_nil(row["sdss_dr"]),
        redshift_z: to_float_or_nil(row["redshift_z"]),
        source_catalog: "local",
        created_at: now,
        updated_at: now
      }
    end

    records.select! { |record| record[:name].present? && record[:ra].present? && record[:dec].present? }
    MigrationGalaxy.insert_all(records) if records.any?
  end

  def down
    MigrationGalaxy.where(source_catalog: "local").delete_all
  end

  private

  def parse_boolean(value)
    value.to_s.strip.casecmp("true").zero?
  end

  def to_float_or_nil(value)
    return nil if value.nil?

    stripped = value.to_s.strip
    return nil if stripped.empty?

    Float(stripped)
  rescue ArgumentError, TypeError
    nil
  end

  def blank_to_nil(value)
    stripped = value.to_s.strip
    stripped.empty? ? nil : stripped
  end
end
