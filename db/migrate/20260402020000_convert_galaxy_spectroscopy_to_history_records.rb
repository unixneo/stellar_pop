class ConvertGalaxySpectroscopyToHistoryRecords < ActiveRecord::Migration[7.1]
  def change
    remove_index :galaxy_spectroscopies, :galaxy_id
    add_index :galaxy_spectroscopies, :galaxy_id

    add_column :galaxy_spectroscopies, :current, :boolean, null: false, default: true
    add_column :galaxy_spectroscopies, :spec_objid, :string
    add_column :galaxy_spectroscopies, :source_release, :string
    add_column :galaxy_spectroscopies, :match_type, :string
    add_column :galaxy_spectroscopies, :match_distance_arcsec, :float

    add_index :galaxy_spectroscopies, %i[galaxy_id current]
  end
end
