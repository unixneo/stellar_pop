namespace :benchmarks do
  desc "Debug age-flip behavior by comparing benchmark winner vs old-age candidate for one galaxy"
  task :debug_age_flip, [:galaxy_name, :run_id, :age_old, :z_old] => :environment do |_t, args|
    galaxy_name = (args[:galaxy_name].presence || "NGC4564").to_s
    age_old = (args[:age_old].presence || "13.0").to_f
    z_old_arg = args[:z_old]
    run_id = args[:run_id].presence

    run = select_run(run_id, galaxy_name)
    payload = JSON.parse(run.result_json.presence || "{}")
    benchmark = Array(payload["benchmarks"]).find { |row| row["name"].to_s == galaxy_name }
    raise "Galaxy '#{galaxy_name}' not found in benchmark run #{run.id}" unless benchmark

    winner = extract_candidate(benchmark["best_fit"] || Array(benchmark["top_results"]).first || {})
    raise "No winner candidate found for '#{galaxy_name}' in run #{run.id}" if winner.empty?

    challenger = winner.dup
    challenger[:age_gyr] = age_old
    challenger[:metallicity_z] = z_old_arg.present? ? z_old_arg.to_f : challenger[:metallicity_z]

    photometry = normalize_photometry(benchmark["photometry"] || {})

    mode = payload["mode"].to_s
    config = PipelineConfig.current
    profile = profile_for_mode(mode, config)
    bench_idx = Array(payload["benchmarks"]).index(benchmark) || 0
    winner_seed = seed_for_candidate(profile, bench_idx, winner)
    challenger_seed = seed_for_candidate(profile, bench_idx, challenger)

    winner_eval = evaluate_candidate(winner, photometry, winner_seed)
    challenger_eval = evaluate_candidate(challenger, photometry, challenger_seed)

    puts "run_id=#{run.id} run_name=#{run.name}"
    puts "galaxy=#{galaxy_name}"
    puts "mode=#{mode.presence || 'unknown'} bench_idx=#{bench_idx}"
    puts "winner=#{winner.inspect}"
    puts "winner_seed=#{winner_seed.inspect}"
    puts "challenger=#{challenger.inspect}"
    puts "challenger_seed=#{challenger_seed.inspect}"
    puts format("winner_chi2=%.6f challenger_chi2=%.6f delta(challenger-winner)=%.6f",
                winner_eval[:chi_squared], challenger_eval[:chi_squared], challenger_eval[:chi_squared] - winner_eval[:chi_squared])
    puts
    puts "Per-band chi-squared terms:"
    puts "band | winner_delta | challenger_delta | winner_term | challenger_term"
    %i[u g r i z].each do |band|
      wd = winner_eval[:per_band][band]
      cd = challenger_eval[:per_band][band]
      puts format("%4s | %12.6f | %16.6f | %11.6f | %14.6f",
                  band.to_s, wd[:delta], cd[:delta], wd[:term], cd[:term])
    end
  end

  def select_run(run_id, galaxy_name)
    if run_id.present?
      return BenchmarkRun.find(run_id)
    end

    BenchmarkRun.where(status: "complete").order(created_at: :desc).find do |candidate|
      payload = JSON.parse(candidate.result_json.presence || "{}")
      Array(payload["benchmarks"]).any? { |row| row["name"].to_s == galaxy_name }
    end || raise("No completed benchmark run found containing '#{galaxy_name}'")
  end

  def extract_candidate(row)
    raw = row.to_h
    {
      age_gyr: raw["age_gyr"] || raw[:age_gyr],
      metallicity_z: raw["metallicity_z"] || raw[:metallicity_z],
      sfh_model: raw["sfh_model"] || raw[:sfh_model],
      imf_type: raw["imf_type"] || raw[:imf_type],
      burst_age_gyr: raw["burst_age_gyr"] || raw[:burst_age_gyr]
    }.transform_values { |v| v.is_a?(String) ? v.strip : v }.reject { |_k, v| v.nil? || v == "" }
  end

  def normalize_photometry(raw)
    data = raw.to_h
    %i[u g r i z redshift_z].each_with_object({}) do |key, out|
      out[key] = (data[key.to_s] || data[key]).to_f
    end
  end

  def evaluate_candidate(candidate, photometry, seed = nil)
    grid_job = GridFitJob.new
    config = PipelineConfig.current
    blackboard = grid_job.send(
      :build_blackboard,
      age_gyr: candidate.fetch(:age_gyr).to_f,
      metallicity_z: candidate.fetch(:metallicity_z).to_f,
      sfh_model: candidate.fetch(:sfh_model).to_s,
      imf_type: candidate.fetch(:imf_type).to_s,
      burst_age_gyr: candidate[:burst_age_gyr],
      seed: seed || 42,
      config: config
    )

    StellarPop::Integrator::SpectralIntegrator.new(
      blackboard,
      spectra_source: StellarPop::KnowledgeSources::BaselSpectra.new
    ).run

    composite = blackboard.read(:composite_spectrum) || {}
    per_band = chi_squared_terms(composite, photometry)
    chi_squared = per_band.values.sum { |row| row[:term] }

    { chi_squared: chi_squared, per_band: per_band }
  end

  def profile_for_mode(mode, config)
    if mode == "fast"
      {
        ages: config.float_array("calibration_fast_ages_gyr"),
        metallicities: config.float_array("calibration_fast_metallicities_z"),
        sfh_models: config.string_array("calibration_fast_sfh_models"),
        imf_types: config.string_array("calibration_fast_imf_types"),
        burst_ages: config.float_array("calibration_fast_burst_ages_gyr")
      }
    else
      {
        ages: config.float_array("grid_ages_gyr"),
        metallicities: config.float_array("grid_metallicities_z"),
        sfh_models: config.string_array("grid_sfh_models"),
        imf_types: config.string_array("grid_imf_types"),
        burst_ages: config.float_array("grid_burst_ages_gyr")
      }
    end
  end

  def seed_for_candidate(profile, bench_idx, candidate)
    target_age = candidate.fetch(:age_gyr).to_f
    target_z = candidate.fetch(:metallicity_z).to_f
    target_sfh = candidate.fetch(:sfh_model).to_s
    target_imf = candidate.fetch(:imf_type).to_s
    target_burst =
      if candidate[:burst_age_gyr].nil?
        nil
      else
        candidate[:burst_age_gyr].to_f
      end

    combination_index = 0
    profile[:ages].each do |age_gyr|
      profile[:metallicities].each do |metallicity_z|
        profile[:sfh_models].each do |sfh_model|
          burst_ages = sfh_model.to_s == "burst" ? profile[:burst_ages] : [nil]
          burst_ages.each do |burst_age_gyr|
            profile[:imf_types].each do |imf_type|
              same =
                float_same?(age_gyr, target_age) &&
                float_same?(metallicity_z, target_z) &&
                sfh_model.to_s == target_sfh &&
                imf_type.to_s == target_imf &&
                burst_same?(burst_age_gyr, target_burst)
              return ((bench_idx + 1) * 1_000_000) + combination_index if same

              combination_index += 1
            end
          end
        end
      end
    end

    nil
  end

  def float_same?(a, b, eps = 1.0e-9)
    (a.to_f - b.to_f).abs <= eps
  end

  def burst_same?(a, b, eps = 1.0e-9)
    return true if a.nil? && b.nil?
    return false if a.nil? || b.nil?

    (a.to_f - b.to_f).abs <= eps
  end

  def chi_squared_terms(composite_spectrum, photometry)
    convolver = StellarPop::SdssFilterConvolver.new
    synthetic_fluxes = convolver.synthetic_magnitudes(composite_spectrum)

    bands = %i[u g r i z]
    corrected = StellarPop::KCorrection.correct(
      bands.index_with { |band| photometry.fetch(band).to_f },
      photometry.fetch(:redshift_z).to_f
    )

    observed_fluxes = bands.index_with { |band| 10.0**(-corrected[band].to_f / 2.5) }

    synthetic_mags = synthetic_fluxes.transform_values do |flux|
      v = flux.to_f
      v.positive? ? (-2.5 * Math.log10(v)) : 999.0
    end
    observed_mags = observed_fluxes.transform_values do |flux|
      v = flux.to_f
      v.positive? ? (-2.5 * Math.log10(v)) : 999.0
    end

    norm_syn = synthetic_mags.transform_values { |m| m - synthetic_mags[:r] }
    norm_obs = observed_mags.transform_values { |m| m - observed_mags[:r] }

    sigma_floor = GridFitJob::MAG_SIGMA_FLOOR
    sigma_r = sigma_floor

    bands.each_with_object({}) do |band, out|
      delta = norm_syn[band].to_f - norm_obs[band].to_f
      variance = (sigma_floor**2) + (sigma_r**2)
      term = (delta**2) / variance
      out[band] = { delta: delta, term: term }
    end
  end
end
