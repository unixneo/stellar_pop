class SynthesisPipelineJob < ApplicationJob
  queue_as :synthesis

  AGE_BINS_GYR = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0].freeze
  DEFAULT_WAVELENGTH_RANGE_NM = (350.0..900.0)
  SDSS_BAND_CENTERS_NM = {
    u: 354.0,
    g: 477.0,
    r: 623.0,
    i: 763.0,
    z: 913.0
  }.freeze

  def perform(synthesis_run_id)
    synthesis_run = SynthesisRun.find(synthesis_run_id)
    synthesis_run.update!(status: "running", error_message: nil)

    blackboard = StellarPop::Blackboard.new

    imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new(seed: synthesis_run.id.to_i)
    imf_masses = imf_sampler.sample(1000)

    sfh_model = StellarPop::KnowledgeSources::SfhModel.new
    sfh_model_symbol = normalize_sfh_model(synthesis_run.sfh_model)
    sfh_weights = build_sfh_weights(sfh_model, sfh_model_symbol, synthesis_run.age_gyr.to_f)

    blackboard.write(:imf_masses, imf_masses)
    blackboard.write(:age_gyr, synthesis_run.age_gyr.to_f)
    blackboard.write(:metallicity_z, synthesis_run.metallicity_z.to_f)
    blackboard.write(:sfh_model, sfh_model_symbol)
    blackboard.write(:sdss_ra, synthesis_run.sdss_ra)
    blackboard.write(:sdss_dec, synthesis_run.sdss_dec)
    blackboard.write(:age_bins, AGE_BINS_GYR)
    blackboard.write(:sfh_weights, sfh_weights)
    blackboard.write(:wavelength_range, DEFAULT_WAVELENGTH_RANGE_NM)

    integrator = StellarPop::Integrator::SpectralIntegrator.new(blackboard)
    integrator.run
    composite_spectrum = blackboard.read(:composite_spectrum) || {}

    sdss_photometry = nil
    chi_squared = nil
    if non_zero_coordinates?(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
      sdss_client = StellarPop::SdssClient.new
      sdss_photometry = sdss_client.fetch_photometry(synthesis_run.sdss_ra, synthesis_run.sdss_dec)
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

    synthesis_run.update!(status: "complete", error_message: nil, chi_squared: chi_squared)
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

  def build_sfh_weights(sfh_model, sfh_model_symbol, run_age_gyr)
    case sfh_model_symbol
    when :exponential
      sfh_model.weights(:exponential, AGE_BINS_GYR, tau: 3.0)
    when :burst
      burst_age = run_age_gyr.positive? ? run_age_gyr : 2.0
      sfh_model.weights(:burst, AGE_BINS_GYR, burst_age_gyr: burst_age, width_gyr: 1.0)
    else
      sfh_model.weights(:constant, AGE_BINS_GYR, {})
    end
  end

  def non_zero_coordinates?(ra, dec)
    !ra.to_f.zero? && !dec.to_f.zero?
  end

  def compute_chi_squared(composite_spectrum, sdss_photometry)
    return nil if composite_spectrum.nil? || composite_spectrum.empty?

    SDSS_BAND_CENTERS_NM.sum do |band, center_nm|
      observed_mag = sdss_photometry[band]
      next 0.0 if observed_mag.nil?

      observed_flux = 10.0**(-observed_mag.to_f / 2.5)
      next 0.0 unless observed_flux.positive?

      synthetic_flux = nearest_synthetic_flux(composite_spectrum, center_nm)
      next 0.0 if synthetic_flux.nil?

      ((synthetic_flux - observed_flux)**2) / observed_flux
    end
  end

  def nearest_synthetic_flux(composite_spectrum, target_wavelength_nm)
    nearest_wavelength = composite_spectrum.keys.min_by { |wl| (wl.to_f - target_wavelength_nm).abs }
    return nil if nearest_wavelength.nil?

    composite_spectrum[nearest_wavelength].to_f
  end
end
