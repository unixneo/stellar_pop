class BenchmarkRunJob < ApplicationJob
  queue_as :benchmark

  class CancelledError < StandardError; end
  CHI_SQUARED_PASS_MAX = 0.20

  def perform(benchmark_run_id, options = {})
    config = PipelineConfig.current
    progress_write_every = [config.int_value("calibration_progress_write_every"), 1].max
    started_at = Time.current
    benchmark_run = BenchmarkRun.find(benchmark_run_id)
    benchmark_run.update!(
      status: "running",
      error_message: nil,
      progress_completed: 0,
      progress_total: 0,
      current_step: "Initializing benchmarks"
    )

    benchmarks = selected_benchmarks(options)
    raise "No calibration benchmarks configured" if benchmarks.empty?

    grid_job = GridFitJob.new
    profile = grid_profile(options, config)
    total_steps = benchmarks.size * combinations_per_benchmark(profile)
    completed_steps = 0
    benchmark_run.update!(progress_total: total_steps, current_step: "Starting benchmark sweep")

    benchmark_results = benchmarks.each_with_index.map do |benchmark, bench_idx|
      photometry = benchmark_photometry(benchmark)
      step_label = "Benchmark #{bench_idx + 1}/#{benchmarks.size}: #{benchmark[:name]}"
      benchmark_run.update_columns(current_step: step_label)

      ranked = run_grid_for_photometry(benchmark_run_id, grid_job, photometry, bench_idx, profile, config) do
        completed_steps += 1
        if (completed_steps % progress_write_every).zero? || completed_steps == total_steps
          benchmark_run.update_columns(
            progress_completed: completed_steps,
            current_step: step_label,
            updated_at: Time.current
          )
        end
      end
      best = ranked.first || {}
      evaluation = evaluate_best_fit(best, benchmark)
      photometric_diagnostics = build_photometric_diagnostics(best, photometry, grid_job, bench_idx, config)
      stellar_mass_comparison = compare_stellar_mass(best, benchmark, photometry)

      {
        key: benchmark[:key],
        name: benchmark[:name],
        type: benchmark[:type],
        benchmark_type: benchmark[:benchmark_type],
        ra: benchmark[:ra],
        dec: benchmark[:dec],
        references: Array(benchmark[:references]),
        notes: benchmark[:notes],
        expected: benchmark[:expected],
        photometry: photometry,
        best_fit: best,
        photometric_diagnostics: photometric_diagnostics,
        stellar_mass_comparison: stellar_mass_comparison,
        verdict: evaluation[:verdict],
        checks: evaluation[:checks],
        top_results: ranked.first(20)
      }
    end

    summary = {
      total: benchmark_results.size,
      pass: benchmark_results.count { |row| row[:verdict] == "pass" },
      warn: benchmark_results.count { |row| row[:verdict] == "warn" },
      fail: benchmark_results.count { |row| row[:verdict] == "fail" }
    }

    result_payload = {
      generated_at: Time.current.iso8601,
      mode: profile[:mode],
      summary: summary,
      benchmarks: benchmark_results
    }

    validation_failed = summary[:fail].to_i.positive?
    benchmark_run.update!(
      status: validation_failed ? "failed" : "complete",
      result_json: result_payload.to_json,
      error_message: validation_failed ? "Validation gate failed: one or more benchmarks are outside accepted limits." : nil,
      runtime_seconds: elapsed_seconds(started_at),
      progress_completed: total_steps,
      progress_total: total_steps,
      current_step: "Completed"
    )
  rescue CancelledError
    benchmark_run&.update!(
      status: "failed",
      error_message: "Cancelled by user",
      runtime_seconds: elapsed_seconds(started_at),
      current_step: "Cancelled by user"
    )
  rescue StandardError => e
    benchmark_run&.update!(
      status: "failed",
      error_message: e.message,
      runtime_seconds: elapsed_seconds(started_at),
      current_step: "Failed"
    )
  end

  private

  def selected_benchmarks(options)
    sdss_release = PipelineConfig.current.sdss_dataset_release
    all = StellarPop::Calibration::BenchmarkCatalog.all(sdss_release: sdss_release)
    requested = Array(options[:benchmark_keys] || options["benchmark_keys"]).map(&:to_s).uniq
    return [] if requested.empty?

    filtered = all.select { |benchmark| requested.include?(benchmark[:key].to_s) }
    filtered
  end

  def run_grid_for_photometry(benchmark_run_id, grid_job, photometry, bench_idx, profile, config)
    results = []
    combination_index = 0

    profile[:ages].each do |age_gyr|
      profile[:metallicities].each do |metallicity_z|
        profile[:sfh_models].each do |sfh_model|
          burst_ages_for_model(sfh_model, profile).each do |burst_age_gyr|
            profile[:imf_types].each do |imf_type|
              seed = (bench_idx + 1) * 1_000_000 + combination_index
              blackboard = grid_job.send(
                :build_blackboard,
                age_gyr: age_gyr,
                metallicity_z: metallicity_z,
                sfh_model: sfh_model,
                imf_type: imf_type,
                burst_age_gyr: burst_age_gyr,
                seed: seed,
                config: config
              )

              StellarPop::Integrator::SpectralIntegrator.new(
                blackboard,
                spectra_source: StellarPop::KnowledgeSources::BaselSpectra.new
              ).run

              composite = blackboard.read(:composite_spectrum) || {}
              chi_squared = grid_job.send(:compute_chi_squared, composite, photometry)

              results << {
                age_gyr: age_gyr,
                metallicity_z: metallicity_z,
                sfh_model: sfh_model,
                burst_age_gyr: burst_age_gyr,
                imf_type: imf_type,
                chi_squared: chi_squared
              }

              combination_index += 1
              raise CancelledError if cancellation_requested?(benchmark_run_id)
              yield if block_given?
            end
          end
        end
      end
    end

    results.sort_by { |row| row[:chi_squared].to_f }
  end

  def combinations_per_benchmark(profile)
    non_burst_models = profile[:sfh_models].reject { |name| name == "burst" }.size
    sfh_effective = non_burst_models + profile[:burst_ages].size

    profile[:ages].size *
      profile[:metallicities].size *
      profile[:imf_types].size *
      sfh_effective
  end

  def burst_ages_for_model(sfh_model, profile)
    return profile[:burst_ages] if sfh_model.to_s == "burst"

    [nil]
  end

  def grid_profile(options, config)
    fast_mode = ActiveModel::Type::Boolean.new.cast(options[:fast_mode] || options["fast_mode"])
    return full_profile(config) unless fast_mode

    {
      mode: "fast",
      ages: config.float_array("calibration_fast_ages_gyr"),
      metallicities: config.float_array("calibration_fast_metallicities_z"),
      sfh_models: config.string_array("calibration_fast_sfh_models"),
      imf_types: config.string_array("calibration_fast_imf_types"),
      burst_ages: config.float_array("calibration_fast_burst_ages_gyr")
    }
  end

  def full_profile(config)
    {
      mode: "full",
      ages: config.float_array("grid_ages_gyr"),
      metallicities: config.float_array("grid_metallicities_z"),
      sfh_models: config.string_array("grid_sfh_models"),
      imf_types: config.string_array("grid_imf_types"),
      burst_ages: config.float_array("grid_burst_ages_gyr")
    }
  end

  def benchmark_photometry(benchmark)
    source = benchmark[:photometry] || {}
    {
      u: source[:u].to_f,
      g: source[:g].to_f,
      r: source[:r].to_f,
      i: source[:i].to_f,
      z: source[:z].to_f,
      redshift_z: source[:redshift_z].to_f
    }
  end

  def evaluate_best_fit(best, benchmark)
    expected = benchmark[:expected] || {}

    age = best[:age_gyr].to_f
    z = best[:metallicity_z].to_f
    sfh = best[:sfh_model].to_s
    chi_squared = best[:chi_squared].to_f

    age_ok = age >= expected.fetch(:age_gyr_min, age) && age <= expected.fetch(:age_gyr_max, age)
    metallicity_ok = z >= expected.fetch(:metallicity_z_min, z) && z <= expected.fetch(:metallicity_z_max, z)
    allowed_sfh = Array(expected[:sfh_models]).map(&:to_s)
    sfh_ok = allowed_sfh.empty? || allowed_sfh.include?(sfh)
    chi_squared_ok = chi_squared.finite? && chi_squared >= 0.0 && chi_squared <= CHI_SQUARED_PASS_MAX

    checks = {
      age_ok: age_ok,
      metallicity_ok: metallicity_ok,
      sfh_ok: sfh_ok,
      chi_squared_ok: chi_squared_ok
    }

    verdict = if checks.values.all?
      "pass"
    elsif !chi_squared_ok || checks.values.count(false) >= 2
      "fail"
    else
      "warn"
    end

    { verdict: verdict, checks: checks }
  end

  def build_photometric_diagnostics(best, photometry, grid_job, bench_idx, config)
    return {} unless best.is_a?(Hash)
    return {} if photometry.blank?

    blackboard = grid_job.send(
      :build_blackboard,
      age_gyr: best[:age_gyr] || best["age_gyr"],
      metallicity_z: best[:metallicity_z] || best["metallicity_z"],
      sfh_model: best[:sfh_model] || best["sfh_model"],
      imf_type: best[:imf_type] || best["imf_type"],
      burst_age_gyr: best[:burst_age_gyr] || best["burst_age_gyr"],
      seed: (bench_idx + 1) * 9_000_000 + 7,
      config: config
    )

    StellarPop::Integrator::SpectralIntegrator.new(
      blackboard,
      spectra_source: StellarPop::KnowledgeSources::BaselSpectra.new
    ).run
    composite = blackboard.read(:composite_spectrum) || {}
    return {} if composite.empty?

    convolver = StellarPop::SdssFilterConvolver.new
    synthetic_fluxes = convolver.synthetic_magnitudes(composite)
    synthetic_mags = to_magnitudes(synthetic_fluxes)

    observed_input = {
      u: photometry[:u] || photometry["u"],
      g: photometry[:g] || photometry["g"],
      r: photometry[:r] || photometry["r"],
      i: photometry[:i] || photometry["i"],
      z: photometry[:z] || photometry["z"]
    }
    corrected_observed = StellarPop::KCorrection.correct(
      observed_input,
      photometry[:redshift_z] || photometry["redshift_z"]
    )

    color_pairs = {
      "u-r" => %i[u r],
      "g-r" => %i[g r],
      "i-r" => %i[i r],
      "z-r" => %i[z r]
    }

    colors = {}
    color_pairs.each do |label, (num, den)|
      observed = corrected_observed[num].to_f - corrected_observed[den].to_f
      synthetic = synthetic_mags[num].to_f - synthetic_mags[den].to_f
      colors[label] = {
        observed: observed,
        synthetic: synthetic,
        delta: synthetic - observed
      }
    end

    {
      chi_squared: compute_chi_squared(composite, photometry),
      chi_squared_pass_max: CHI_SQUARED_PASS_MAX,
      colors: colors
    }
  rescue StandardError
    {}
  end

  def to_magnitudes(fluxes)
    fluxes.transform_values do |value|
      flux = value.to_f
      flux.positive? ? (-2.5 * Math.log10(flux)) : 999.0
    end
  end

  def compare_stellar_mass(best, benchmark, photometry)
    expected = benchmark[:expected] || {}
    observed_min = expected[:stellar_mass_min] || expected["stellar_mass_min"]
    observed_max = expected[:stellar_mass_max] || expected["stellar_mass_max"]
    observed_mass =
      if observed_min && observed_max
        (observed_min.to_f + observed_max.to_f) / 2.0
      elsif observed_min
        observed_min.to_f
      elsif observed_max
        observed_max.to_f
      end

    sps_mass = estimate_sps_stellar_mass(best, photometry)
    return {} if observed_mass.nil? || sps_mass.nil?
    return {} unless observed_mass.positive? && sps_mass.positive?

    delta = sps_mass - observed_mass

    {
      sps_stellar_mass: sps_mass,
      observed_stellar_mass: observed_mass,
      delta_stellar_mass: delta,
      ratio_sps_to_observed: sps_mass / observed_mass
    }
  end

  def estimate_sps_stellar_mass(best, photometry)
    return nil unless best.is_a?(Hash)
    return nil unless photometry.is_a?(Hash)

    StellarPop::StellarMassEstimator.estimate(
      sfh_model: best[:sfh_model] || best["sfh_model"],
      imf_type: best[:imf_type] || best["imf_type"],
      age_gyr: best[:age_gyr] || best["age_gyr"],
      observed_r_mag: photometry[:r] || photometry["r"],
      redshift_z: photometry[:redshift_z] || photometry["redshift_z"],
      burst_age_gyr: best[:burst_age_gyr] || best["burst_age_gyr"]
    )
  end

  def elapsed_seconds(started_at)
    return nil unless started_at

    [(Time.current - started_at).round, 0].max
  end

  def cancellation_requested?(benchmark_run_id)
    BenchmarkRun.where(id: benchmark_run_id, status: "failed", error_message: "Cancelled by user").exists?
  end
end
