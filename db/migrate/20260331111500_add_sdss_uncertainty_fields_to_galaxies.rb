class AddSdssUncertaintyFieldsToGalaxies < ActiveRecord::Migration[7.1]
  def up
    add_column :galaxies, :petro_err_u, :float
    add_column :galaxies, :petro_err_g, :float
    add_column :galaxies, :petro_err_r, :float
    add_column :galaxies, :petro_err_i, :float
    add_column :galaxies, :petro_err_z, :float

    add_column :galaxies, :model_err_u, :float
    add_column :galaxies, :model_err_g, :float
    add_column :galaxies, :model_err_r, :float
    add_column :galaxies, :model_err_i, :float
    add_column :galaxies, :model_err_z, :float

    add_column :galaxies, :z_err, :float
    add_column :galaxies, :z_warning, :integer
    add_column :galaxies, :sdss_clean, :boolean
  end

  def down
    remove_column :galaxies, :sdss_clean
    remove_column :galaxies, :z_warning
    remove_column :galaxies, :z_err

    remove_column :galaxies, :model_err_z
    remove_column :galaxies, :model_err_i
    remove_column :galaxies, :model_err_r
    remove_column :galaxies, :model_err_g
    remove_column :galaxies, :model_err_u

    remove_column :galaxies, :petro_err_z
    remove_column :galaxies, :petro_err_i
    remove_column :galaxies, :petro_err_r
    remove_column :galaxies, :petro_err_g
    remove_column :galaxies, :petro_err_u
  end
end
