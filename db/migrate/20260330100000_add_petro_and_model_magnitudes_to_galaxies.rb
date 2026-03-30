class AddPetroAndModelMagnitudesToGalaxies < ActiveRecord::Migration[7.1]
  def up
    add_column :galaxies, :petro_u, :float
    add_column :galaxies, :petro_g, :float
    add_column :galaxies, :petro_r, :float
    add_column :galaxies, :petro_i, :float
    add_column :galaxies, :petro_z, :float

    add_column :galaxies, :model_u, :float
    add_column :galaxies, :model_g, :float
    add_column :galaxies, :model_r, :float
    add_column :galaxies, :model_i, :float
    add_column :galaxies, :model_z, :float
  end

  def down
    remove_column :galaxies, :petro_u
    remove_column :galaxies, :petro_g
    remove_column :galaxies, :petro_r
    remove_column :galaxies, :petro_i
    remove_column :galaxies, :petro_z

    remove_column :galaxies, :model_u
    remove_column :galaxies, :model_g
    remove_column :galaxies, :model_r
    remove_column :galaxies, :model_i
    remove_column :galaxies, :model_z
  end
end
