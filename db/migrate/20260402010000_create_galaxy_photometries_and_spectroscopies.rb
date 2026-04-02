class CreateGalaxyPhotometriesAndSpectroscopies < ActiveRecord::Migration[7.1]
  def change
    create_table :galaxy_photometries do |t|
      t.references :galaxy, null: false, foreign_key: true, index: { unique: true }

      t.float :mag_u
      t.float :mag_g
      t.float :mag_r
      t.float :mag_i
      t.float :mag_z

      t.float :petro_u
      t.float :petro_g
      t.float :petro_r
      t.float :petro_i
      t.float :petro_z

      t.float :model_u
      t.float :model_g
      t.float :model_r
      t.float :model_i
      t.float :model_z

      t.float :err_u
      t.float :err_g
      t.float :err_r
      t.float :err_i
      t.float :err_z

      t.float :petro_err_u
      t.float :petro_err_g
      t.float :petro_err_r
      t.float :petro_err_i
      t.float :petro_err_z

      t.float :model_err_u
      t.float :model_err_g
      t.float :model_err_r
      t.float :model_err_i
      t.float :model_err_z

      t.float :extinction_u
      t.float :extinction_g
      t.float :extinction_r
      t.float :extinction_i
      t.float :extinction_z

      t.string :mag_type
      t.boolean :sdss_clean
      t.string :id_match_quality
      t.float :id_match_distance_arcsec
      t.text :id_match_note
      t.string :sdss_dr

      t.timestamps
    end

    create_table :galaxy_spectroscopies do |t|
      t.references :galaxy, null: false, foreign_key: true, index: { unique: true }

      t.float :redshift_z
      t.float :z_err
      t.integer :z_warning
      t.string :redshift_source
      t.string :redshift_confidence
      t.datetime :redshift_checked_at
      t.string :sdss_dr

      t.timestamps
    end
  end
end
