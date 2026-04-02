class AddLuminosityDistanceLyToGalaxies < ActiveRecord::Migration[7.1]
  def change
    add_column :galaxies, :luminosity_distance_ly, :float
  end
end
