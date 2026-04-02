class GalaxySpectroscopiesController < ApplicationController
  before_action :set_galaxy

  def edit
    @spectroscopy = GalaxySpectroscopy.find_or_initialize_by(galaxy_id: @galaxy.id)
  end

  def update
    @spectroscopy = GalaxySpectroscopy.find_or_initialize_by(galaxy_id: @galaxy.id)
    if @spectroscopy.update(spectroscopy_params)
      redirect_to galaxy_path(@galaxy), notice: "Spectroscopy updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_galaxy
    @galaxy = Galaxy.find(params[:galaxy_id])
  end

  def spectroscopy_params
    params.require(:galaxy_spectroscopy).permit(
      :redshift_z, :z_err, :z_warning, :redshift_source, :redshift_confidence, :redshift_checked_at, :sdss_dr
    )
  end
end
