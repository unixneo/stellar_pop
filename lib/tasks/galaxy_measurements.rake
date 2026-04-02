namespace :galaxies do
  desc "Backfill galaxy_photometries and galaxy_spectroscopies from existing galaxies columns"
  task backfill_measurement_tables: :environment do
    galaxies = Galaxy.order(:id)
    if galaxies.none?
      puts "No galaxies found."
      next
    end

    photo_count = 0
    spec_count = 0

    Galaxy.transaction do
      galaxies.find_each(batch_size: 500) do |galaxy|
        photometry_attrs = {
          mag_u: galaxy.mag_u,
          mag_g: galaxy.mag_g,
          mag_r: galaxy.mag_r,
          mag_i: galaxy.mag_i,
          mag_z: galaxy.mag_z,
          petro_u: galaxy.petro_u,
          petro_g: galaxy.petro_g,
          petro_r: galaxy.petro_r,
          petro_i: galaxy.petro_i,
          petro_z: galaxy.petro_z,
          model_u: galaxy.model_u,
          model_g: galaxy.model_g,
          model_r: galaxy.model_r,
          model_i: galaxy.model_i,
          model_z: galaxy.model_z,
          err_u: galaxy.err_u,
          err_g: galaxy.err_g,
          err_r: galaxy.err_r,
          err_i: galaxy.err_i,
          err_z: galaxy.err_z,
          petro_err_u: galaxy.petro_err_u,
          petro_err_g: galaxy.petro_err_g,
          petro_err_r: galaxy.petro_err_r,
          petro_err_i: galaxy.petro_err_i,
          petro_err_z: galaxy.petro_err_z,
          model_err_u: galaxy.model_err_u,
          model_err_g: galaxy.model_err_g,
          model_err_r: galaxy.model_err_r,
          model_err_i: galaxy.model_err_i,
          model_err_z: galaxy.model_err_z,
          extinction_u: galaxy.extinction_u,
          extinction_g: galaxy.extinction_g,
          extinction_r: galaxy.extinction_r,
          extinction_i: galaxy.extinction_i,
          extinction_z: galaxy.extinction_z,
          mag_type: galaxy.mag_type,
          sdss_clean: galaxy.sdss_clean,
          id_match_quality: galaxy.id_match_quality,
          id_match_distance_arcsec: galaxy.id_match_distance_arcsec,
          id_match_note: galaxy.id_match_note,
          sdss_dr: galaxy.sdss_dr
        }

        spectroscopy_attrs = {
          redshift_z: galaxy.redshift_z,
          z_err: galaxy.z_err,
          z_warning: galaxy.z_warning,
          redshift_source: galaxy.redshift_source,
          redshift_confidence: galaxy.redshift_confidence,
          redshift_checked_at: galaxy.redshift_checked_at,
          sdss_dr: galaxy.sdss_dr
        }

        photo = GalaxyPhotometry.find_or_initialize_by(galaxy_id: galaxy.id)
        photo.update!(photometry_attrs)
        photo_count += 1

        spec = GalaxySpectroscopy.find_or_initialize_by(galaxy_id: galaxy.id)
        spec.update!(spectroscopy_attrs)
        spec_count += 1
      end
    end

    puts "Backfill complete:"
    puts "  galaxy_photometries rows upserted: #{photo_count}"
    puts "  galaxy_spectroscopies rows upserted: #{spec_count}"
  end
end
