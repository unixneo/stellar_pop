class GalaxySpectroscopiesController < ApplicationController
  before_action :set_galaxy
  before_action :set_spectroscopy, only: %i[edit update destroy]

  def new
    @spectroscopy = @galaxy.galaxy_spectroscopies.new(current: false, sdss_dr: @galaxy.sdss_dr)
  end

  def create
    @spectroscopy = @galaxy.galaxy_spectroscopies.new(spectroscopy_params)
    if @spectroscopy.save
      redirect_to galaxy_path(@galaxy), notice: "Spectroscopy record created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @spectroscopy.update(spectroscopy_params)
      redirect_to galaxy_path(@galaxy), notice: "Spectroscopy updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @spectroscopy.destroy!
    redirect_to galaxy_path(@galaxy), notice: "Spectroscopy record deleted."
  end

  private

  def set_galaxy
    @galaxy = Galaxy.find(params[:galaxy_id])
  end

  def set_spectroscopy
    @spectroscopy = @galaxy.galaxy_spectroscopies.find(params[:id])
  end

  def spectroscopy_params
    params.require(:galaxy_spectroscopy).permit(
      :redshift_z, :z_err, :z_warning, :redshift_source, :redshift_confidence, :redshift_checked_at, :sdss_dr,
      :current, :spec_objid, :source_release, :match_type, :match_distance_arcsec
    )
  end
end
