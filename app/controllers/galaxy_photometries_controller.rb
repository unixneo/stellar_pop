class GalaxyPhotometriesController < ApplicationController
  before_action :set_galaxy

  def edit
    @photometry = GalaxyPhotometry.find_or_initialize_by(galaxy_id: @galaxy.id)
  end

  def update
    @photometry = GalaxyPhotometry.find_or_initialize_by(galaxy_id: @galaxy.id)
    if @photometry.update(photometry_params)
      redirect_to galaxy_path(@galaxy), notice: "Photometry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_galaxy
    @galaxy = Galaxy.find(params[:galaxy_id])
  end

  def photometry_params
    params.require(:galaxy_photometry).permit(
      :mag_u, :mag_g, :mag_r, :mag_i, :mag_z,
      :petro_u, :petro_g, :petro_r, :petro_i, :petro_z,
      :model_u, :model_g, :model_r, :model_i, :model_z,
      :err_u, :err_g, :err_r, :err_i, :err_z,
      :petro_err_u, :petro_err_g, :petro_err_r, :petro_err_i, :petro_err_z,
      :model_err_u, :model_err_g, :model_err_r, :model_err_i, :model_err_z,
      :extinction_u, :extinction_g, :extinction_r, :extinction_i, :extinction_z,
      :mag_type, :sdss_clean, :id_match_quality, :id_match_distance_arcsec, :id_match_note, :sdss_dr
    )
  end
end
