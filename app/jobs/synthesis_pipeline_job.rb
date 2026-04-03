class SynthesisPipelineJob < ApplicationJob
  queue_as :synthesis
  MAG_SIGMA_FLOOR = 0.03

  def perform(synthesis_run_id)
    config = PipelineConfig.current
    sdss_release = config.sdss_dataset_release
    age_bins_gyr = config.float_array("synthesis_age_bins_gyr")
    imf_sample_size = config.int_value("synthesis_imf_sample_size")
    synthesis_run = SynthesisRun.find(synthesis_run_id)
    synthesis_run.update!(status: "running", error_message: nil, chi_squared: nil, stellar_mass: nil)

    blackboard = StellarPop::Blackboard.new

    imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new(
      seed: synthesis_run.id.to_i,
      imf_type: synthesis_run.imf_type.to_sym
    )
    imf_masses = imf_sampler.sample(imf_sample_size)

    sfh_model = StellarPop::KnowledgeSources::SfhModel.new
    sfh_model_symbol = normalize_sfh_model(synthesis_run.sfh_model)
    sfh_weights = build_sfh_weights(sfh_model, sfh_model_symbol, synthesis_run, age_bins_gyr, config)
    run_age_gyr = synthesis_run.age_gyr.to_f
    run_age_gyr = age_bins_gyr.first.to_f unless run_age_gyr.positive?
    wavelength_range = build_wavelength_range(synthesis_run, config)

    blackboard.write(:imf_masses, imf_masses)
    blackboard.write(:age_gyr, run_age_gyr)
    blackboard.write(:metallicity_z, synthesis_run.metallicity_z.to_f)
    blackboard.write(:sfh_model, sfh_model_symbol)
    blackboard.write(:sdss_ra, synthesis_run.sdss_ra)
    blackboard.write(:sdss_dec, synthesis_run.sdss_dec)
    blackboard.write(:age_bins, age_bins_gyr)
    blackboard.write(:sfh_weights, sfh_weights)
    blackboard.write(:wavelength_range, wavelength_range)

    spectra_source = build_spectra_source(synthesis_run.spectra_model)
    integrator = StellarPop::Integrator::SpectralIntegrator.new(blackboard, spectra_source: spectra_source)
    integrator.run
    composite_spectrum = blackboard.read(:composite_spectrum) || {}

    sdss_photometry = nil
    chi_squared = nil
    stellar_mass = nil
    sdss_fetch_note = nil
    sdss_object_name = nil
    sdss_required = non_zero_coordinates?(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
    if sdss_required
      galaxy_target = synthesis_run.galaxy || Galaxy.find_by_ra_dec(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
      if galaxy_target
        sdss_photometry = galaxy_target.photometry_hash
        sdss_object_name = galaxy_target.name
        synthesis_run.galaxy_id ||= galaxy_target.id
        sdss_fetch_note = "SDSS photometry sourced from galaxies table"
      else
        sdss_client = StellarPop::SdssClient.new(release: sdss_release)
        sdss_photometry, live_failure_reason = fetch_sdss_photometry_with_retry(
          sdss_client,
          synthesis_run.sdss_ra,
          synthesis_run.sdss_dec,
          config
        )
        sdss_fetch_note =
          if sdss_photometry
            "SDSS photometry sourced from live SDSS API"
          else
            build_sdss_unavailable_note(live_failure_reason)
          end
      end
      chi_squared = compute_chi_squared(composite_spectrum, sdss_photometry) if sdss_photometry
      stellar_mass = estimate_stellar_mass(synthesis_run, sdss_photometry, chi_squared, config)
    end

    wavelengths = composite_spectrum.keys.sort
    fluxes = wavelengths.map { |wl| composite_spectrum[wl] }

    SpectrumResult.create!(
      synthesis_run: synthesis_run,
      wavelength_data: wavelengths.to_json,
      flux_data: fluxes.to_json,
      sdss_photometry: sdss_photometry&.to_json
    )

    final_status =
      if sdss_required && sdss_photometry.nil?
        "failed"
      else
        "complete"
      end

    synthesis_run.update!(
      status: final_status,
      error_message: sdss_fetch_note,
      chi_squared: chi_squared,
      stellar_mass: stellar_mass,
      galaxy_id: synthesis_run.galaxy_id,
      sdss_object_name: sdss_object_name
    )
  rescue StandardError => e
    synthesis_run&.update(status: "failed", error_message: e.message)
  end

  private

  def normalize_sfh_model(raw_model)
    model = raw_model.to_s.strip.downcase
    return :exponential if model == "exponential"
    return :delayed_exponential if model == "delayed_exponential"
    return :burst if model == "burst"

    :constant
  end

  def build_sfh_weights(sfh_model, sfh_model_symbol, synthesis_run, age_bins_gyr, config)
    case sfh_model_symbol
    when :exponential
      sfh_model.weights(:exponential, age_bins_gyr, tau: config.float_value("synthesis_exponential_tau"))
    when :delayed_exponential
      sfh_model.weights(:delayed_exponential, age_bins_gyr, tau: config.float_value("synthesis_delayed_exponential_tau"))
    when :burst
      burst_age = synthesis_run.burst_age_gyr.to_f
      burst_width = synthesis_run.burst_width_gyr.to_f
      burst_age = config.float_value("synthesis_burst_default_age_gyr") unless burst_age.positive?
      burst_width = config.float_value("synthesis_burst_default_width_gyr") unless burst_width.positive?
      sfh_model.weights(:burst, age_bins_gyr, burst_age_gyr: burst_age, width_gyr: burst_width)
    else
      sfh_model.weights(:constant, age_bins_gyr, {})
    end
  end

  def build_spectra_source(raw_spectra_model)
    model = raw_spectra_model.to_s.strip.downcase
    return StellarPop::KnowledgeSources::StellarSpectra.new if model == "planck"

    StellarPop::KnowledgeSources::BaselSpectra.new
  end

  def build_wavelength_range(synthesis_run, config)
    min_nm = synthesis_run.wavelength_min.to_f
    max_nm = synthesis_run.wavelength_max.to_f
    min_nm = config.float_value("synthesis_default_wavelength_min_nm") unless min_nm.positive?
    max_nm = config.float_value("synthesis_default_wavelength_max_nm") unless max_nm.positive?
    min_nm, max_nm = [min_nm, max_nm].minmax

    min_nm..max_nm
  end

  def non_zero_coordinates?(ra, dec)
    !ra.to_f.zero? && !dec.to_f.zero?
  end

  def fetch_sdss_photometry_with_retry(sdss_client, ra, dec, config)
    max_fetch_attempts = [config.int_value("synthesis_sdss_max_fetch_attempts"), 1].max
    base_backoff_seconds = [config.float_value("synthesis_sdss_base_backoff_seconds"), 0.0].max
    attempt = 0
    last_reason = nil

    while attempt < max_fetch_attempts
      attempt += 1
      photometry = sdss_client.fetch_photometry(ra, dec)
      return [photometry, nil] if photometry
      last_reason = sdss_client.respond_to?(:last_failure_reason) ? sdss_client.last_failure_reason : nil

      break if attempt >= max_fetch_attempts

      sleep_backoff(base_backoff_seconds * (2**(attempt - 1)))
    end

    [nil, last_reason]
  end

  def sleep_backoff(seconds)
    sleep(seconds)
  end

  def compute_chi_squared(composite_spectrum, sdss_photometry)
    return nil if composite_spectrum.nil? || composite_spectrum.empty?
    convolver = StellarPop::SdssFilterConvolver.new
    synthetic_fluxes = convolver.synthetic_magnitudes(composite_spectrum)

    bands = %i[u g r i z]
    observed_magnitudes = {}
    bands.each do |band|
      observed_mag = sdss_photometry[band] || sdss_photometry[band.to_s]
      return nil if observed_mag.nil?

      observed_magnitudes[band] = observed_mag.to_f
    end

    corrected_magnitudes = StellarPop::KCorrection.correct(
      observed_magnitudes,
      sdss_photometry[:redshift_z] || sdss_photometry["redshift_z"]
    )

    observed_fluxes = {}
    bands.each do |band|
      observed_flux = 10.0**(-corrected_magnitudes[band].to_f / 2.5)
      return nil unless observed_flux.positive?

      observed_fluxes[band] = observed_flux
    end

    synthetic_mags = synthetic_fluxes.transform_values do |flux|
      flux_value = flux.to_f
      flux_value.positive? ? (-2.5 * Math.log10(flux_value)) : 999.0
    end
    observed_mags = observed_fluxes.transform_values do |flux|
      flux_value = flux.to_f
      flux_value.positive? ? (-2.5 * Math.log10(flux_value)) : 999.0
    end

    norm_syn = synthetic_mags.transform_values { |magnitude| magnitude - synthetic_mags[:r] }
    norm_obs = observed_mags.transform_values { |magnitude| magnitude - observed_mags[:r] }

    bands.sum do |band|
      delta = norm_syn[band].to_f - norm_obs[band].to_f
      sigma_band = magnitude_sigma_for(sdss_photometry, band)
      sigma_r = magnitude_sigma_for(sdss_photometry, :r)
      variance = (sigma_band**2) + (sigma_r**2)
      variance = (MAG_SIGMA_FLOOR**2) if variance <= 0.0
      (delta**2) / variance
    end
  end

  def magnitude_sigma_for(sdss_photometry, band)
    raw = sdss_photometry[:"err_#{band}"] || sdss_photometry["err_#{band}"]
    sigma = raw.to_f
    return MAG_SIGMA_FLOOR unless sigma.finite? && sigma.positive?

    [sigma, MAG_SIGMA_FLOOR].max
  end

  def build_sdss_unavailable_note(reason)
    case reason
    when :no_object_found
      "SDSS photometry unavailable: local catalog miss; live SDSS API reachable but no nearby object found."
    when :timeout
      "SDSS photometry unavailable: local catalog miss; live SDSS API timed out."
    when :api_unreachable
      "SDSS photometry unavailable: local catalog miss; live SDSS API unreachable."
    when :invalid_response
      "SDSS photometry unavailable: local catalog miss; live SDSS API returned invalid response."
    else
      "SDSS photometry unavailable: local catalog miss; live SDSS API request failed."
    end
  end

  def estimate_stellar_mass(synthesis_run, sdss_photometry, chi_squared, config)
    return nil if sdss_photometry.nil?
    return nil if chi_squared.nil?

    redshift = sdss_photometry[:redshift_z] || sdss_photometry["redshift_z"]
    return nil unless redshift.to_f.positive?

    observed_r_mag = corrected_r_band_magnitude(sdss_photometry, redshift)
    return nil if observed_r_mag.nil?

    StellarPop::StellarMassEstimator.estimate(
      sfh_model: synthesis_run.sfh_model,
      imf_type: synthesis_run.imf_type,
      age_gyr: synthesis_run.age_gyr,
      observed_r_mag: observed_r_mag,
      redshift_z: redshift,
      burst_age_gyr: synthesis_run.burst_age_gyr,
      mass_log_offset_dex: config.float_value("calibration_mass_log_offset_dex")
    )
  end

  def corrected_r_band_magnitude(sdss_photometry, redshift)
    bands = %i[u g r i z]
    observed_magnitudes = {}
    bands.each do |band|
      observed_mag = sdss_photometry[band] || sdss_photometry[band.to_s]
      return nil if observed_mag.nil?

      observed_magnitudes[band] = observed_mag.to_f
    end

    corrected = StellarPop::KCorrection.correct(observed_magnitudes, redshift)
    corrected[:r]
  end
end
