class PipelineConfig < ApplicationRecord
  DEFAULTS = {
    "synthesis_age_bins_gyr" => [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0],
    "synthesis_imf_sample_size" => 1000,
    "synthesis_exponential_tau" => 3.0,
    "synthesis_delayed_exponential_tau" => 3.0,
    "synthesis_burst_default_age_gyr" => 2.0,
    "synthesis_burst_default_width_gyr" => 0.5,
    "synthesis_default_wavelength_min_nm" => 350.0,
    "synthesis_default_wavelength_max_nm" => 900.0,
    "synthesis_sdss_max_fetch_attempts" => 3,
    "synthesis_sdss_base_backoff_seconds" => 0.5,
    "grid_ages_gyr" => [0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 8.0, 10.0, 12.0],
    "grid_metallicities_z" => [0.0006, 0.0020, 0.0063, 0.0200, 0.0632],
    "grid_sfh_models" => %w[exponential delayed_exponential constant burst],
    "grid_imf_types" => %w[kroupa salpeter chabrier],
    "grid_burst_ages_gyr" => [0.1, 0.5, 1.0, 2.0],
    "grid_age_bins_gyr" => [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0],
    "grid_imf_sample_size" => 1000,
    "grid_wavelength_min_nm" => 350.0,
    "grid_wavelength_max_nm" => 2000.0,
    "grid_exponential_tau" => 3.0,
    "grid_delayed_exponential_tau" => 3.0,
    "grid_burst_width_gyr" => 0.5,
    "grid_sdss_max_fetch_attempts" => 3,
    "grid_sdss_base_backoff_seconds" => 0.5,
    "calibration_progress_write_every" => 10,
    "calibration_fast_ages_gyr" => [0.1, 0.5, 2.0, 8.0, 12.0],
    "calibration_fast_metallicities_z" => [0.0020, 0.0200],
    "calibration_fast_sfh_models" => %w[exponential delayed_exponential constant burst],
    "calibration_fast_imf_types" => %w[kroupa salpeter],
    "calibration_fast_burst_ages_gyr" => [0.5, 2.0]
  }.freeze

  def self.current
    first_or_create!(settings_json: DEFAULTS.to_json)
  end

  def settings
    defaults = DEFAULTS.deep_dup
    defaults.merge(parsed_settings)
  end

  def fetch(key)
    settings.fetch(key.to_s)
  end

  def float_array(key)
    Array(fetch(key)).map(&:to_f)
  end

  def string_array(key)
    Array(fetch(key)).map(&:to_s)
  end

  def float_value(key)
    fetch(key).to_f
  end

  def int_value(key)
    fetch(key).to_i
  end

  def update_from_form(form_params)
    merged = settings

    assign_list(merged, "synthesis_age_bins_gyr", form_params[:synthesis_age_bins_gyr], :float)
    assign_scalar(merged, "synthesis_imf_sample_size", form_params[:synthesis_imf_sample_size], :int)
    assign_scalar(merged, "synthesis_exponential_tau", form_params[:synthesis_exponential_tau], :float)
    assign_scalar(merged, "synthesis_delayed_exponential_tau", form_params[:synthesis_delayed_exponential_tau], :float)
    assign_scalar(merged, "synthesis_burst_default_age_gyr", form_params[:synthesis_burst_default_age_gyr], :float)
    assign_scalar(merged, "synthesis_burst_default_width_gyr", form_params[:synthesis_burst_default_width_gyr], :float)
    assign_scalar(merged, "synthesis_default_wavelength_min_nm", form_params[:synthesis_default_wavelength_min_nm], :float)
    assign_scalar(merged, "synthesis_default_wavelength_max_nm", form_params[:synthesis_default_wavelength_max_nm], :float)
    assign_scalar(merged, "synthesis_sdss_max_fetch_attempts", form_params[:synthesis_sdss_max_fetch_attempts], :int)
    assign_scalar(merged, "synthesis_sdss_base_backoff_seconds", form_params[:synthesis_sdss_base_backoff_seconds], :float)

    assign_list(merged, "grid_ages_gyr", form_params[:grid_ages_gyr], :float)
    assign_list(merged, "grid_metallicities_z", form_params[:grid_metallicities_z], :float)
    assign_list(merged, "grid_sfh_models", form_params[:grid_sfh_models], :string)
    assign_list(merged, "grid_imf_types", form_params[:grid_imf_types], :string)
    assign_list(merged, "grid_burst_ages_gyr", form_params[:grid_burst_ages_gyr], :float)
    assign_list(merged, "grid_age_bins_gyr", form_params[:grid_age_bins_gyr], :float)
    assign_scalar(merged, "grid_imf_sample_size", form_params[:grid_imf_sample_size], :int)
    assign_scalar(merged, "grid_wavelength_min_nm", form_params[:grid_wavelength_min_nm], :float)
    assign_scalar(merged, "grid_wavelength_max_nm", form_params[:grid_wavelength_max_nm], :float)
    assign_scalar(merged, "grid_exponential_tau", form_params[:grid_exponential_tau], :float)
    assign_scalar(merged, "grid_delayed_exponential_tau", form_params[:grid_delayed_exponential_tau], :float)
    assign_scalar(merged, "grid_burst_width_gyr", form_params[:grid_burst_width_gyr], :float)
    assign_scalar(merged, "grid_sdss_max_fetch_attempts", form_params[:grid_sdss_max_fetch_attempts], :int)
    assign_scalar(merged, "grid_sdss_base_backoff_seconds", form_params[:grid_sdss_base_backoff_seconds], :float)

    assign_scalar(merged, "calibration_progress_write_every", form_params[:calibration_progress_write_every], :int)
    assign_list(merged, "calibration_fast_ages_gyr", form_params[:calibration_fast_ages_gyr], :float)
    assign_list(merged, "calibration_fast_metallicities_z", form_params[:calibration_fast_metallicities_z], :float)
    assign_list(merged, "calibration_fast_sfh_models", form_params[:calibration_fast_sfh_models], :string)
    assign_list(merged, "calibration_fast_imf_types", form_params[:calibration_fast_imf_types], :string)
    assign_list(merged, "calibration_fast_burst_ages_gyr", form_params[:calibration_fast_burst_ages_gyr], :float)

    update!(settings_json: merged.to_json)
  end

  private

  def parsed_settings
    JSON.parse(settings_json.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def assign_list(target, key, raw, type)
    return if raw.nil?

    parsed = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    return if parsed.empty?

    target[key] =
      case type
      when :float
        parsed.map(&:to_f)
      when :string
        parsed.map(&:to_s)
      else
        parsed
      end
  end

  def assign_scalar(target, key, raw, type)
    return if raw.nil? || raw.to_s.strip.empty?

    target[key] =
      case type
      when :int
        raw.to_i
      when :float
        raw.to_f
      else
        raw
      end
  end
end
