class DropLegacyMeasurementColumnsFromGalaxies < ActiveRecord::Migration[7.1]
  def change
    remove_columns :galaxies,
      :mag_u, :mag_g, :mag_r, :mag_i, :mag_z,
      :err_u, :err_g, :err_r, :err_i, :err_z,
      :extinction_u, :extinction_g, :extinction_r, :extinction_i, :extinction_z,
      :redshift_z,
      :mag_type,
      :petro_u, :petro_g, :petro_r, :petro_i, :petro_z,
      :model_u, :model_g, :model_r, :model_i, :model_z,
      :petro_err_u, :petro_err_g, :petro_err_r, :petro_err_i, :petro_err_z,
      :model_err_u, :model_err_g, :model_err_r, :model_err_i, :model_err_z,
      :z_err, :z_warning, :sdss_clean,
      :id_match_quality, :id_match_distance_arcsec, :id_match_note,
      :redshift_source, :redshift_confidence, :redshift_checked_at
  end
end
