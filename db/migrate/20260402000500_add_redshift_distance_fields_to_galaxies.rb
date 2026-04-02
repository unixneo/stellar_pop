class AddRedshiftDistanceFieldsToGalaxies < ActiveRecord::Migration[7.1]
  def change
    add_column :galaxies, :luminosity_distance_mpc, :float
    add_column :galaxies, :distance_calc_method, :string
    add_column :galaxies, :distance_updated_at, :datetime
  end
end
