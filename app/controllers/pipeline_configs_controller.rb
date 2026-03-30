class PipelineConfigsController < ApplicationController
  def show
    @pipeline_config = PipelineConfig.current
    @settings = @pipeline_config.settings
  end

  def edit
    @pipeline_config = PipelineConfig.current
    @settings = @pipeline_config.settings
  end

  def update
    @pipeline_config = PipelineConfig.current
    @pipeline_config.update_from_form(config_params)
    redirect_to pipeline_config_path, notice: "Pipeline configuration updated."
  rescue StandardError => e
    @settings = @pipeline_config.settings
    flash.now[:alert] = "Unable to update configuration: #{e.message}"
    render :edit, status: :unprocessable_entity
  end

  def reset
    @pipeline_config = PipelineConfig.current
    @pipeline_config.update!(settings_json: PipelineConfig::DEFAULTS.to_json)
    redirect_to pipeline_config_path, notice: "Pipeline configuration reset to defaults."
  end

  private

  def config_params
    params.require(:pipeline_config).permit(
      :synthesis_age_bins_gyr,
      :synthesis_imf_sample_size,
      :synthesis_exponential_tau,
      :synthesis_delayed_exponential_tau,
      :synthesis_burst_default_age_gyr,
      :synthesis_burst_default_width_gyr,
      :synthesis_default_wavelength_min_nm,
      :synthesis_default_wavelength_max_nm,
      :synthesis_permit_celestial_coordinate_searches,
      :synthesis_sdss_max_fetch_attempts,
      :synthesis_sdss_base_backoff_seconds,
      :sdss_dataset_release,
      :grid_ages_gyr,
      :grid_metallicities_z,
      :grid_sfh_models,
      :grid_imf_types,
      :grid_burst_ages_gyr,
      :grid_age_bins_gyr,
      :grid_imf_sample_size,
      :grid_wavelength_min_nm,
      :grid_wavelength_max_nm,
      :grid_exponential_tau,
      :grid_delayed_exponential_tau,
      :grid_burst_width_gyr,
      :grid_sdss_max_fetch_attempts,
      :grid_sdss_base_backoff_seconds,
      :calibration_progress_write_every,
      :calibration_fast_ages_gyr,
      :calibration_fast_metallicities_z,
      :calibration_fast_sfh_models,
      :calibration_fast_imf_types,
      :calibration_fast_burst_ages_gyr
    )
  end
end
