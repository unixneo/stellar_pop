class SynthesisPipelineJob < ApplicationJob
  queue_as :synthesis

  AGE_BINS_GYR = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0].freeze
  DEFAULT_WAVELENGTH_MIN_NM = 350.0
  DEFAULT_WAVELENGTH_MAX_NM = 900.0
  SDSS_MAX_FETCH_ATTEMPTS = 3
  SDSS_BASE_BACKOFF_SECONDS = 0.5

  def perform(synthesis_run_id)
    synthesis_run = SynthesisRun.find(synthesis_run_id)
    synthesis_run.update!(status: "running", error_message: nil)

    blackboard = StellarPop::Blackboard.new

    imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new(
      seed: synthesis_run.id.to_i,
      imf_type: synthesis_run.imf_type.to_sym
    )
    imf_masses = imf_sampler.sample(1000)

    sfh_model = StellarPop::KnowledgeSources::SfhModel.new
    sfh_model_symbol = normalize_sfh_model(synthesis_run.sfh_model)
    sfh_weights = build_sfh_weights(sfh_model, sfh_model_symbol, synthesis_run)
    run_age_gyr = synthesis_run.age_gyr.to_f
    run_age_gyr = AGE_BINS_GYR.first.to_f unless run_age_gyr.positive?
    wavelength_range = build_wavelength_range(synthesis_run)

    blackboard.write(:imf_masses, imf_masses)
    blackboard.write(:age_gyr, run_age_gyr)
    blackboard.write(:metallicity_z, synthesis_run.metallicity_z.to_f)
    blackboard.write(:sfh_model, sfh_model_symbol)
    blackboard.write(:sdss_ra, synthesis_run.sdss_ra)
    blackboard.write(:sdss_dec, synthesis_run.sdss_dec)
    blackboard.write(:age_bins, AGE_BINS_GYR)
    blackboard.write(:sfh_weights, sfh_weights)
    blackboard.write(:wavelength_range, wavelength_range)

    spectra_source = build_spectra_source(synthesis_run.spectra_model)
    integrator = StellarPop::Integrator::SpectralIntegrator.new(blackboard, spectra_source: spectra_source)
    integrator.run
    composite_spectrum = blackboard.read(:composite_spectrum) || {}

    sdss_photometry = nil
    chi_squared = nil
    sdss_fetch_note = nil
    sdss_object_name = nil
    sdss_required = non_zero_coordinates?(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
    if sdss_required
      local_target = StellarPop::SdssLocalCatalog.lookup_target(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
      if local_target
        sdss_photometry = {
          u: local_target[:u],
          g: local_target[:g],
          r: local_target[:r],
          i: local_target[:i],
          z: local_target[:z],
          redshift_z: local_target[:redshift_z]
        }
        sdss_object_name = local_target[:name]
        sdss_fetch_note = "SDSS photometry sourced from local catalog"
      else
        sdss_client = StellarPop::SdssClient.new
        sdss_photometry, live_failure_reason = fetch_sdss_photometry_with_retry(
          sdss_client,
          synthesis_run.sdss_ra,
          synthesis_run.sdss_dec
        )
        sdss_fetch_note =
          if sdss_photometry
            "SDSS photometry sourced from live SDSS API"
          else
            build_sdss_unavailable_note(live_failure_reason)
          end
      end
      chi_squared = compute_chi_squared(composite_spectrum, sdss_photometry) if sdss_photometry
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
      sdss_object_name: sdss_object_name
    )
  rescue StandardError => e
    synthesis_run&.update(status: "failed", error_message: e.message)
  end

  private

  def normalize_sfh_model(raw_model)
    model = raw_model.to_s.strip.downcase
    return :exponential if model == "exponential"
    return :burst if model == "burst"

    :constant
  end

  def build_sfh_weights(sfh_model, sfh_model_symbol, synthesis_run)
    case sfh_model_symbol
    when :exponential
      sfh_model.weights(:exponential, AGE_BINS_GYR, tau: 3.0)
    when :burst
      burst_age = synthesis_run.burst_age_gyr.to_f
      burst_width = synthesis_run.burst_width_gyr.to_f
      burst_age = 2.0 unless burst_age.positive?
      burst_width = 0.5 unless burst_width.positive?
      sfh_model.weights(:burst, AGE_BINS_GYR, burst_age_gyr: burst_age, width_gyr: burst_width)
    else
      sfh_model.weights(:constant, AGE_BINS_GYR, {})
    end
  end

  def build_spectra_source(raw_spectra_model)
    model = raw_spectra_model.to_s.strip.downcase
    return StellarPop::KnowledgeSources::StellarSpectra.new if model == "planck"

    StellarPop::KnowledgeSources::BaselSpectra.new
  end

  def weighted_mean_age(age_bins, sfh_weights)
    numerator = age_bins.zip(sfh_weights).sum { |age, weight| age.to_f * weight.to_f }
    denominator = sfh_weights.sum(&:to_f)
    return age_bins.first.to_f unless denominator.positive?

    numerator / denominator
  end

  def build_wavelength_range(synthesis_run)
    min_nm = synthesis_run.wavelength_min.to_f
    max_nm = synthesis_run.wavelength_max.to_f
    min_nm = DEFAULT_WAVELENGTH_MIN_NM unless min_nm.positive?
    max_nm = DEFAULT_WAVELENGTH_MAX_NM unless max_nm.positive?
    min_nm, max_nm = [min_nm, max_nm].minmax

    min_nm..max_nm
  end

  def non_zero_coordinates?(ra, dec)
    !ra.to_f.zero? && !dec.to_f.zero?
  end

  def fetch_sdss_photometry_with_retry(sdss_client, ra, dec)
    attempt = 0
    last_reason = nil

    while attempt < SDSS_MAX_FETCH_ATTEMPTS
      attempt += 1
      photometry = sdss_client.fetch_photometry(ra, dec)
      return [photometry, nil] if photometry
      last_reason = sdss_client.respond_to?(:last_failure_reason) ? sdss_client.last_failure_reason : nil

      break if attempt >= SDSS_MAX_FETCH_ATTEMPTS

      sleep_backoff(SDSS_BASE_BACKOFF_SECONDS * (2**(attempt - 1)))
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
      delta**2
    end
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
end
