class CreateGallazziCatalogTables < ActiveRecord::Migration[7.1]
  def change
    create_table :gallazzi_stellar_metallicities do |t|
      t.integer :plateid, null: false
      t.integer :mjd, null: false
      t.integer :fiberid, null: false
      t.float :p2p5, null: false
      t.float :p16, null: false
      t.float :median_log_z, null: false
      t.float :p84, null: false
      t.float :p97p5, null: false
      t.float :mode_log_z, null: false
      t.integer :sdss_index
      t.string :source_release, null: false, default: "DR2"
      t.string :source_file, null: false, default: "gallazzi_z_star.txt"
      t.timestamps
    end

    add_index :gallazzi_stellar_metallicities, [:plateid, :mjd, :fiberid], unique: true, name: "idx_gallazzi_metals_plate_mjd_fiber"

    create_table :gallazzi_rband_weighted_ages do |t|
      t.integer :plateid, null: false
      t.integer :mjd, null: false
      t.integer :fiberid, null: false
      t.float :p2p5_log_yr, null: false
      t.float :p16_log_yr, null: false
      t.float :median_log_yr, null: false
      t.float :p84_log_yr, null: false
      t.float :p97p5_log_yr, null: false
      t.float :mode_log_yr, null: false
      t.integer :sdss_index
      t.string :source_release, null: false, default: "DR2"
      t.string :source_file, null: false, default: "gallazzi_lwage.txt"
      t.timestamps
    end

    add_index :gallazzi_rband_weighted_ages, [:plateid, :mjd, :fiberid], unique: true, name: "idx_gallazzi_ages_plate_mjd_fiber"
  end
end
