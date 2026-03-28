class GridFitJob < ApplicationJob
  queue_as :synthesis

  AGES_GYR = [0.01, 0.05, 0.1, 0.5, 1.0, 3.0, 5.0, 8.0, 10.0, 12.0].freeze
  METALLICITIES_Z = [0.0006, 0.0020, 0.0063, 0.0200, 0.0632].freeze
  SFH_MODELS = %w[exponential constant burst].freeze
  IMF_TYPES = %w[kroupa salpeter].freeze
  AGE_BINS_GYR = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0].freeze
  WAVELENGTH_RANGE_NM = (350.0..2000.0).freeze
  SDSS_MAX_FETCH_ATTEMPTS = 3
  SDSS_BASE_BACKOFF_SECONDS = 0.5

  def perform(grid_fit_id, sweep_options = {})
    started_at = Time.current
    grid_fit = GridFit.find(grid_fit_id)
    grid_fit.update!(status: "running", error_message: nil)
    selected_ages = sanitize_float_array(sweep_options["ages_gyr"] || sweep_options[:ages_gyr], AGES_GYR)
    selected_metallicities = sanitize_float_array(sweep_options["metallicities_z"] || sweep_options[:metallicities_z], METALLICITIES_Z)
    selected_sfh_models = sanitize_string_array(sweep_options["sfh_models"] || sweep_options[:sfh_models], SFH_MODELS)
    selected_imf_types = sanitize_string_array(sweep_options["imf_types"] || sweep_options[:imf_types], IMF_TYPES)

    sdss_target = StellarPop::SdssLocalCatalog.lookup_target(grid_fit.sdss_ra, grid_fit.sdss_dec)
    sdss_photometry = if sdss_target
      build_photometry_hash(sdss_target)
    else
      fetch_sdss_photometry_with_retry(StellarPop::SdssClient.new, grid_fit.sdss_ra, grid_fit.sdss_dec)
    end

    unless sdss_photometry
      grid_fit.update!(
        status: "failed",
        error_message: "SDSS photometry unavailable - local catalog miss and live API timeout or no object found",
        runtime_seconds: elapsed_seconds(started_at)
      )
      return
    end

    grid_fit.update!(target_name: sdss_target&.dig(:name) || grid_fit.target_name)

    results = []
    combination_index = 0

    selected_ages.each do |age_gyr|
      selected_metallicities.each do |metallicity_z|
        selected_sfh_models.each do |sfh_model|
          selected_imf_types.each do |imf_type|
            blackboard = build_blackboard(
              age_gyr: age_gyr,
              metallicity_z: metallicity_z,
              sfh_model: sfh_model,
              imf_type: imf_type,
              seed: grid_fit.id.to_i * 10_000 + combination_index
            )

            integrator = StellarPop::Integrator::SpectralIntegrator.new(
              blackboard,
              spectra_source: StellarPop::KnowledgeSources::BaselSpectra.new
            )
            integrator.run
            composite_spectrum = blackboard.read(:composite_spectrum) || {}

            chi_squared = compute_chi_squared(composite_spectrum, sdss_photometry)
            results << {
              age_gyr: age_gyr,
              metallicity_z: metallicity_z,
              sfh_model: sfh_model,
              imf_type: imf_type,
              chi_squared: chi_squared
            }

            combination_index += 1
          end
        end
      end
    end

    ranked = results.sort_by { |row| row[:chi_squared].to_f }
    best = ranked.first || {}

    grid_fit.update!(
      status: "complete",
      best_age_gyr: best[:age_gyr],
      best_metallicity_z: best[:metallicity_z],
      best_sfh_model: best[:sfh_model],
      best_imf_type: best[:imf_type],
      best_chi_squared: best[:chi_squared],
      result_json: ranked.to_json,
      runtime_seconds: elapsed_seconds(started_at)
    )
  rescue StandardError => e
    grid_fit&.update(status: "failed", error_message: e.message, runtime_seconds: elapsed_seconds(started_at))
  end

  private

  def build_blackboard(age_gyr:, metallicity_z:, sfh_model:, imf_type:, seed:)
    blackboard = StellarPop::Blackboard.new

    imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new(seed: seed, imf_type: imf_type.to_sym)
    imf_masses = imf_sampler.sample(1000)

    age_bins = build_age_bins_for_sweep(age_gyr)
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    sfh_weights = build_sfh_weights(sfh, sfh_model, age_gyr, age_bins)

    blackboard.write(:imf_masses, imf_masses)
    blackboard.write(:age_gyr, age_gyr.to_f)
    blackboard.write(:metallicity_z, metallicity_z.to_f)
    blackboard.write(:sfh_model, sfh_model.to_sym)
    blackboard.write(:age_bins, age_bins)
    blackboard.write(:sfh_weights, sfh_weights)
    blackboard.write(:wavelength_range, WAVELENGTH_RANGE_NM)
    blackboard
  end

  def build_sfh_weights(sfh, sfh_model, age_gyr, age_bins)
    case sfh_model
    when "exponential"
      sfh.weights(:exponential, age_bins, tau: 3.0)
    when "burst"
      sfh.weights(:burst, age_bins, burst_age_gyr: age_gyr.to_f, width_gyr: 0.5)
    else
      sfh.weights(:constant, age_bins, {})
    end
  end

  def build_age_bins_for_sweep(age_gyr)
    target_age = age_gyr.to_f
    bins = AGE_BINS_GYR.select { |value| value <= target_age }
    bins << target_age unless bins.include?(target_age)
    bins = [target_age] if bins.empty?
    bins.sort.uniq
  end

  def weighted_mean_age(age_bins, sfh_weights)
    numerator = age_bins.zip(sfh_weights).sum { |age, weight| age.to_f * weight.to_f }
    denominator = sfh_weights.sum(&:to_f)
    return age_bins.first.to_f unless denominator.positive?

    numerator / denominator
  end

  def build_photometry_hash(target)
    {
      u: target[:u],
      g: target[:g],
      r: target[:r],
      i: target[:i],
      z: target[:z]
    }
  end

  def fetch_sdss_photometry_with_retry(sdss_client, ra, dec)
    attempt = 0

    while attempt < SDSS_MAX_FETCH_ATTEMPTS
      attempt += 1
      photometry = sdss_client.fetch_photometry(ra, dec)
      return photometry if photometry

      break if attempt >= SDSS_MAX_FETCH_ATTEMPTS

      sleep_backoff(SDSS_BASE_BACKOFF_SECONDS * (2**(attempt - 1)))
    end

    nil
  end

  def sleep_backoff(seconds)
    sleep(seconds)
  end

  def compute_chi_squared(composite_spectrum, sdss_photometry)
    return Float::INFINITY if composite_spectrum.nil? || composite_spectrum.empty?

    convolver = StellarPop::SdssFilterConvolver.new
    synthetic_fluxes = convolver.synthetic_magnitudes(composite_spectrum)

    bands = %i[u g r i z]
    observed_fluxes = {}
    bands.each do |band|
      observed_mag = sdss_photometry[band]
      return Float::INFINITY if observed_mag.nil?

      observed_flux = 10.0**(-observed_mag.to_f / 2.5)
      return Float::INFINITY unless observed_flux.positive?

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

  def sanitize_float_array(raw_values, allowed_values)
    selected = Array(raw_values).map { |v| v.to_f }.select { |v| allowed_values.include?(v) }.uniq
    selected.empty? ? allowed_values : selected
  end

  def sanitize_string_array(raw_values, allowed_values)
    selected = Array(raw_values).map(&:to_s).select { |v| allowed_values.include?(v) }.uniq
    selected.empty? ? allowed_values : selected
  end

  def elapsed_seconds(started_at)
    return nil unless started_at

    [(Time.current - started_at).round, 0].max
  end
end
