class AddDataQualityFieldsToGalaxies < ActiveRecord::Migration[7.1]
  def up
    add_column :galaxies, :id_match_quality, :string, default: "unverified", null: false
    add_column :galaxies, :id_match_distance_arcsec, :float
    add_column :galaxies, :id_match_note, :text

    add_column :galaxies, :redshift_source, :string, default: "legacy", null: false
    add_column :galaxies, :redshift_confidence, :string, default: "low", null: false
    add_column :galaxies, :redshift_checked_at, :datetime
  end

  def down
    remove_column :galaxies, :redshift_checked_at
    remove_column :galaxies, :redshift_confidence
    remove_column :galaxies, :redshift_source

    remove_column :galaxies, :id_match_note
    remove_column :galaxies, :id_match_distance_arcsec
    remove_column :galaxies, :id_match_quality
  end
end
