namespace :claude do
  desc "Dump SFH age_bins and weights for a given galaxy fit candidate"
  task :sfh_weights, [:galaxy_name, :age_gyr, :sfh_model, :metallicity_z] => :environment do |_t, args|
    galaxy_name  = args[:galaxy_name].presence  || "NGC4564"
    age_gyr      = (args[:age_gyr].presence     || "12.0").to_f
    sfh_model    = args[:sfh_model].presence    || "exponential"
    metallicity_z = (args[:metallicity_z].presence || "0.02").to_f

    config = PipelineConfig.current
    configured_bins = config.float_array("grid_age_bins_gyr")
    tau = config.float_value("grid_exponential_tau")

    # Mirror the exact logic from GridFitJob#build_age_bins_for_sweep
    bins = configured_bins.select { |v| v <= age_gyr }
    bins << age_gyr unless bins.include?(age_gyr)
    bins = [age_gyr] if bins.empty?
    age_bins = bins.sort.uniq

    sfh = StellarPop::KnowledgeSources::SfhModel.new
    weights = case sfh_model
              when "exponential"
                sfh.weights(:exponential, age_bins, tau: tau)
              when "delayed_exponential"
                sfh.weights(:delayed_exponential, age_bins, tau: tau)
              when "constant"
                sfh.weights(:constant, age_bins, {})
              else
                puts "Unknown sfh_model '#{sfh_model}', defaulting to constant"
                sfh.weights(:constant, age_bins, {})
              end

    # Also compute the alternative formula exp(-(age_gyr - bin)/tau) for comparison
    alt_raw = age_bins.map { |bin| Math.exp(-(age_gyr - bin) / tau) }
    alt_sum = alt_raw.sum
    alt_weights = alt_raw.map { |w| w / alt_sum }

    puts
    puts "=" * 70
    puts "SFH weight diagnostic"
    puts "  galaxy:       #{galaxy_name}"
    puts "  age_gyr:      #{age_gyr}"
    puts "  sfh_model:    #{sfh_model}"
    puts "  metallicity_z: #{metallicity_z}"
    puts "  tau:          #{tau}"
    puts "  configured bins: #{configured_bins.inspect}"
    puts "  selected bins:   #{age_bins.inspect}"
    puts "=" * 70
    puts
    puts format("%-12s  %-10s  %-14s  %-14s  %s",
                "age_bin", "weight", "cumulative", "alt_weight(exp(-(T-t)/tau))", "alt_cumulative")
    puts "-" * 70

    cumulative     = 0.0
    alt_cumulative = 0.0
    age_bins.reverse.each_with_index do |bin, i|
      w   = weights[age_bins.length - 1 - i]
      alt = alt_weights[age_bins.length - 1 - i]
      cumulative     += w
      alt_cumulative += alt
      puts format("%-12.3f  %-10.6f  %-14.6f  %-26.6f  %.6f",
                  bin, w, cumulative, alt, alt_cumulative)
    end

    puts
    puts "Current formula:  exp(-age_bin / tau)          → young bins dominate"
    puts "Alt formula:      exp(-(age_gyr - age_bin) / tau) → old bins dominate"
    puts
    puts "For an old elliptical the dominant stellar population should be OLD."
    puts "Check which weight distribution matches physical expectation."
    puts "=" * 70
  end

  desc "Run benchmark inline for a single galaxy with optional SFH model override, print vs ground truth"
  task :benchmark_single, [:galaxy_name, :sfh_models] => :environment do |_t, args|
    galaxy_name = args[:galaxy_name].presence || "NGC4564"
    sfh_override = args[:sfh_models].presence&.split(",")&.map(&:strip)

    config = PipelineConfig.current
    sdss_release = config.sdss_dataset_release
    catalog = StellarPop::Calibration::BenchmarkCatalog.all(sdss_release: sdss_release)
    key = galaxy_name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    benchmark = catalog.find { |b| b[:key] == key }

    abort "Galaxy '#{galaxy_name}' not found in benchmark catalog (key=#{key})" unless benchmark

    profile = {
      ages:          config.float_array("grid_ages_gyr"),
      metallicities: config.float_array("grid_metallicities_z"),
      sfh_models:    sfh_override || config.string_array("grid_sfh_models"),
      imf_types:     config.string_array("grid_imf_types"),
      burst_ages:    config.float_array("grid_burst_ages_gyr")
    }

    photometry = {
      u: benchmark.dig(:photometry, :u).to_f,
      g: benchmark.dig(:photometry, :g).to_f,
      r: benchmark.dig(:photometry, :r).to_f,
      i: benchmark.dig(:photometry, :i).to_f,
      z: benchmark.dig(:photometry, :z).to_f,
      redshift_z: benchmark.dig(:photometry, :redshift_z).to_f
    }

    expected = benchmark[:expected] || {}
    obs_age  = expected[:age_gyr_min]
    obs_z    = expected[:metallicity_z_min]

    n_combinations = profile[:ages].size * profile[:metallicities].size *
                     profile[:sfh_models].reject { |m| m == "burst" }.size *
                     profile[:imf_types].size
    puts
    puts "=" * 70
    puts "Benchmark: #{galaxy_name}  (key=#{key})"
    puts "SFH models: #{profile[:sfh_models].inspect}"
    puts "Grid size:  #{n_combinations} combinations"
    puts "Photometry: u=#{photometry[:u]} g=#{photometry[:g]} r=#{photometry[:r]} " \
         "i=#{photometry[:i]} z=#{photometry[:z]} z_spec=#{photometry[:redshift_z]}"
    puts "Ground truth (literature): age=#{obs_age&.round(2) || 'n/a'} Gyr  " \
         "metallicity_z=#{obs_z || 'n/a'}"
    puts "  obs counts: age_n=#{expected.dig(:observation_counts, :age_gyr) || 0}  " \
         "z_n=#{expected.dig(:observation_counts, :metallicity_z) || 0}"
    refs = Array(benchmark[:references]).reject(&:empty?)
    puts "  references: #{refs.join('; ')}" if refs.any?
    puts "-" * 70

    grid_job = GridFitJob.new
    results = []
    combination_index = 0
    print "Running grid"

    profile[:ages].each do |age_gyr|
      profile[:metallicities].each do |metallicity_z|
        profile[:sfh_models].each do |sfh_model|
          burst_ages = sfh_model == "burst" ? profile[:burst_ages] : [nil]
          burst_ages.each do |burst_age_gyr|
            profile[:imf_types].each do |imf_type|
              seed = 1_000_000 + combination_index
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
              chi2 = grid_job.send(:compute_chi_squared, composite, photometry)

              results << {
                age_gyr: age_gyr,
                metallicity_z: metallicity_z,
                sfh_model: sfh_model,
                burst_age_gyr: burst_age_gyr,
                imf_type: imf_type,
                chi_squared: chi2
              }

              combination_index += 1
              print "." if (combination_index % 10).zero?
            end
          end
        end
      end
    end

    puts " done (#{combination_index} combos)"
    puts

    ranked = results.sort_by { |r| r[:chi_squared].to_f }
    best   = ranked.first

    age_err = obs_age ? ((best[:age_gyr].to_f - obs_age) / obs_age * 100.0).round(1) : nil
    z_err   = obs_z   ? ((best[:metallicity_z].to_f - obs_z) / obs_z * 100.0).round(1) : nil

    puts "BEST FIT:"
    puts format("  age_gyr:       %.2f   (obs=%.2f, err=%s%%)",
                best[:age_gyr].to_f,
                obs_age.to_f,
                age_err&.to_s || "n/a")
    puts format("  metallicity_z: %.4f (obs=%.4f, err=%s%%)",
                best[:metallicity_z].to_f,
                obs_z.to_f,
                z_err&.to_s || "n/a")
    puts format("  sfh_model:     %s", best[:sfh_model])
    puts format("  imf_type:      %s", best[:imf_type])
    puts format("  chi_squared:   %.6f", best[:chi_squared].to_f)
    puts
    puts "TOP 5:"
    puts format("  %-8s  %-14s  %-12s  %-10s  %s", "age_gyr", "metallicity_z", "sfh_model", "imf_type", "chi2")
    ranked.first(5).each do |r|
      puts format("  %-8.2f  %-14.4f  %-12s  %-10s  %.6f",
                  r[:age_gyr].to_f, r[:metallicity_z].to_f,
                  r[:sfh_model].to_s, r[:imf_type].to_s, r[:chi_squared].to_f)
    end
    puts "=" * 70
  end
end
