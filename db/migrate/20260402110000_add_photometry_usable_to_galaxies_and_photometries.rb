class AddPhotometryUsableToGalaxiesAndPhotometries < ActiveRecord::Migration[7.1]
  def change
    add_column :galaxies, :photometry_usable, :boolean, default: true, null: false
    add_column :galaxy_photometries, :photometry_usable, :boolean, default: true, null: false
  end
end
