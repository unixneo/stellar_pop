class GridFitJob < ApplicationJob
  queue_as :synthesis

  def perform(grid_fit_id, sweep_options = {})
    config = PipelineConfig.current
    sdss_release = config.sdss_dataset_release
    ages_gyr = config.float_array("grid_ages_gyr")
    metallicities_z = config.float_array("grid_metallicities_z")
    sfh_models = config.string_array("grid_sfh_models")
    imf_types = config.string_array("grid_imf_types")
    started_at = Time.current
    grid_fit = GridFit.find(grid_fit_id)
    grid_fit.update!(status: "running", error_message: nil)
    selected_ages = sanitize_float_array(sweep_options["ages_gyr"] || sweep_options[:ages_gyr], ages_gyr)
    selected_metallicities = sanitize_float_array(sweep_options["metallicities_z"] || sweep_options[:metallicities_z], metallicities_z)
    selected_sfh_models = sanitize_string_array(sweep_options["sfh_models"] || sweep_options[:sfh_models], sfh_models)
    selected_imf_types = sanitize_string_array(sweep_options["imf_types"] || sweep_options[:imf_types], imf_types)

    sdss_target = grid_fit.galaxy || Galaxy.find_by_ra_dec(grid_fit.sdss_ra, grid_fit.sdss_dec)
    sdss_photometry, live_failure_reason = if sdss_target
      [build_photometry_hash(sdss_target), nil]
    else
      fetch_sdss_photometry_with_retry(StellarPop::SdssClient.new(release: sdss_release), grid_fit.sdss_ra, grid_fit.sdss_dec, config)
    end

    unless sdss_photometry
      grid_fit.update!(
        status: "failed",
        error_message: build_sdss_unavailable_note(live_failure_reason, sdss_release),
        runtime_seconds: elapsed_seconds(started_at)
      )
      return
    end

    grid_fit.update!(target_name: sdss_target&.name || grid_fit.target_name, galaxy_id: sdss_target&.id || grid_fit.galaxy_id)

    results = []
    combination_index = 0

    selected_ages.each do |age_gyr|
      selected_metallicities.each do |metallicity_z|
        selected_sfh_models.each do |sfh_model|
          burst_ages_for_model(sfh_model, config).each do |burst_age_gyr|
            selected_imf_types.each do |imf_type|
              blackboard = build_blackboard(
                age_gyr: age_gyr,
                metallicity_z: metallicity_z,
                sfh_model: sfh_model,
                imf_type: imf_type,
                burst_age_gyr: burst_age_gyr,
                seed: grid_fit.id.to_i * 10_000 + combination_index,
                config: config
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
                burst_age_gyr: burst_age_gyr,
                imf_type: imf_type,
                chi_squared: chi_squared
              }

              combination_index += 1
            end
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

  def build_blackboard(age_gyr:, metallicity_z:, sfh_model:, imf_type:, burst_age_gyr:, seed:, config:)
    blackboard = StellarPop::Blackboard.new

    imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new(seed: seed, imf_type: imf_type.to_sym)
    imf_masses = imf_sampler.sample(config.int_value("grid_imf_sample_size"))

    age_bins = build_age_bins_for_sweep(age_gyr, config.float_array("grid_age_bins_gyr"))
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    sfh_weights = build_sfh_weights(sfh, sfh_model, age_gyr, burst_age_gyr, age_bins, config)

    blackboard.write(:imf_masses, imf_masses)
    blackboard.write(:age_gyr, age_gyr.to_f)
    blackboard.write(:metallicity_z, metallicity_z.to_f)
    blackboard.write(:sfh_model, sfh_model.to_sym)
    blackboard.write(:age_bins, age_bins)
    blackboard.write(:sfh_weights, sfh_weights)
    blackboard.write(:wavelength_range, build_wavelength_range(config))
    blackboard
  end

  def build_sfh_weights(sfh, sfh_model, _age_gyr, burst_age_gyr, age_bins, config)
    case sfh_model
    when "exponential"
      sfh.weights(:exponential, age_bins, tau: config.float_value("grid_exponential_tau"))
    when "delayed_exponential"
      sfh.weights(:delayed_exponential, age_bins, tau: config.float_value("grid_delayed_exponential_tau"))
    when "burst"
      center = burst_age_gyr.to_f
      center = age_bins.first.to_f unless center.positive?
      sfh.weights(:burst, age_bins, burst_age_gyr: center, width_gyr: config.float_value("grid_burst_width_gyr"))
    else
      sfh.weights(:constant, age_bins, {})
    end
  end

  def burst_ages_for_model(sfh_model, config)
    return config.float_array("grid_burst_ages_gyr") if sfh_model.to_s == "burst"

    [nil]
  end

  def build_age_bins_for_sweep(age_gyr, configured_bins)
    target_age = age_gyr.to_f
    bins = configured_bins.select { |value| value <= target_age }
    bins << target_age unless bins.include?(target_age)
    bins = [target_age] if bins.empty?
    bins.sort.uniq
  end

  def build_photometry_hash(target)
    target.photometry_hash
  end

  def fetch_sdss_photometry_with_retry(sdss_client, ra, dec, config)
    max_fetch_attempts = [config.int_value("grid_sdss_max_fetch_attempts"), 1].max
    base_backoff_seconds = [config.float_value("grid_sdss_base_backoff_seconds"), 0.0].max
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
    return Float::INFINITY if composite_spectrum.nil? || composite_spectrum.empty?

    convolver = StellarPop::SdssFilterConvolver.new
    synthetic_fluxes = convolver.synthetic_magnitudes(composite_spectrum)

    bands = %i[u g r i z]
    observed_magnitudes = {}
    bands.each do |band|
      observed_mag = sdss_photometry[band] || sdss_photometry[band.to_s]
      return Float::INFINITY if observed_mag.nil?

      observed_magnitudes[band] = observed_mag.to_f
    end

    corrected_magnitudes = StellarPop::KCorrection.correct(
      observed_magnitudes,
      sdss_photometry[:redshift_z] || sdss_photometry["redshift_z"]
    )

    observed_fluxes = {}
    bands.each do |band|
      observed_flux = 10.0**(-corrected_magnitudes[band].to_f / 2.5)
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

  def build_sdss_unavailable_note(reason, sdss_release)
    case reason
    when :no_object_found
      "SDSS photometry unavailable: local catalog miss; live SDSS API (#{sdss_release}) reachable but no nearby object found."
    when :timeout
      "SDSS photometry unavailable: local catalog miss; live SDSS API (#{sdss_release}) timed out."
    when :api_unreachable
      "SDSS photometry unavailable: local catalog miss; live SDSS API (#{sdss_release}) unreachable."
    when :invalid_response
      "SDSS photometry unavailable: local catalog miss; live SDSS API (#{sdss_release}) returned invalid response."
    else
      "SDSS photometry unavailable: local catalog miss; live SDSS API (#{sdss_release}) request failed."
    end
  end

  def build_wavelength_range(config)
    min_nm = config.float_value("grid_wavelength_min_nm")
    max_nm = config.float_value("grid_wavelength_max_nm")
    min_nm, max_nm = [min_nm, max_nm].minmax
    min_nm..max_nm
  end
end
