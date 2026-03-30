class AddMagTypeToGalaxies < ActiveRecord::Migration[7.1]
  def change
    add_column :galaxies, :mag_type, :string
  end
end
