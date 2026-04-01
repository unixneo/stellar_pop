class RemoveGallazziTablesFromMainDb < ActiveRecord::Migration[7.1]
  def change
    drop_table :gallazzi_stellar_metallicities, if_exists: true
    drop_table :gallazzi_rband_weighted_ages, if_exists: true
  end
end
