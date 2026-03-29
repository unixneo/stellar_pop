class CalibrationRunJob < ApplicationJob
  queue_as :synthesis
  PROGRESS_WRITE_EVERY = 10

  def perform(calibration_run_id)
    started_at = Time.current
    calibration_run = CalibrationRun.find(calibration_run_id)
    calibration_run.update!(
      status: "running",
      error_message: nil,
      progress_completed: 0,
      progress_total: 0,
      current_step: "Initializing benchmarks"
    )

    benchmarks = StellarPop::Calibration::BenchmarkCatalog.all
    raise "No calibration benchmarks configured" if benchmarks.empty?

    grid_job = GridFitJob.new
    total_steps = benchmarks.size * combinations_per_benchmark
    completed_steps = 0
    calibration_run.update!(progress_total: total_steps, current_step: "Starting benchmark sweep")

    benchmark_results = benchmarks.each_with_index.map do |benchmark, bench_idx|
      photometry = benchmark_photometry(benchmark)
      step_label = "Benchmark #{bench_idx + 1}/#{benchmarks.size}: #{benchmark[:name]}"
      calibration_run.update_columns(current_step: step_label)

      ranked = run_grid_for_photometry(grid_job, photometry, bench_idx) do
        completed_steps += 1
        if (completed_steps % PROGRESS_WRITE_EVERY).zero? || completed_steps == total_steps
          calibration_run.update_columns(
            progress_completed: completed_steps,
            current_step: step_label,
            updated_at: Time.current
          )
        end
      end
      best = ranked.first || {}
      evaluation = evaluate_best_fit(best, benchmark)

      {
        key: benchmark[:key],
        name: benchmark[:name],
        type: benchmark[:type],
        ra: benchmark[:ra],
        dec: benchmark[:dec],
        references: Array(benchmark[:references]),
        expected: benchmark[:expected],
        photometry: photometry,
        best_fit: best,
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
      summary: summary,
      benchmarks: benchmark_results
    }

    calibration_run.update!(
      status: "complete",
      result_json: result_payload.to_json,
      runtime_seconds: elapsed_seconds(started_at),
      progress_completed: total_steps,
      progress_total: total_steps,
      current_step: "Completed"
    )
  rescue StandardError => e
    calibration_run&.update!(
      status: "failed",
      error_message: e.message,
      runtime_seconds: elapsed_seconds(started_at),
      current_step: "Failed"
    )
  end

  private

  def run_grid_for_photometry(grid_job, photometry, bench_idx)
    results = []
    combination_index = 0

    GridFitJob::AGES_GYR.each do |age_gyr|
      GridFitJob::METALLICITIES_Z.each do |metallicity_z|
        GridFitJob::SFH_MODELS.each do |sfh_model|
          burst_ages_for_model(sfh_model).each do |burst_age_gyr|
            GridFitJob::IMF_TYPES.each do |imf_type|
              seed = (bench_idx + 1) * 1_000_000 + combination_index
              blackboard = grid_job.send(
                :build_blackboard,
                age_gyr: age_gyr,
                metallicity_z: metallicity_z,
                sfh_model: sfh_model,
                imf_type: imf_type,
                burst_age_gyr: burst_age_gyr,
                seed: seed
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
              yield if block_given?
            end
          end
        end
      end
    end

    results.sort_by { |row| row[:chi_squared].to_f }
  end

  def combinations_per_benchmark
    non_burst_models = GridFitJob::SFH_MODELS.reject { |name| name == "burst" }.size
    sfh_effective = non_burst_models + GridFitJob::BURST_AGES_GYR.size

    GridFitJob::AGES_GYR.size *
      GridFitJob::METALLICITIES_Z.size *
      GridFitJob::IMF_TYPES.size *
      sfh_effective
  end

  def burst_ages_for_model(sfh_model)
    return GridFitJob::BURST_AGES_GYR if sfh_model.to_s == "burst"

    [nil]
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

    age_ok = age >= expected.fetch(:age_gyr_min, age) && age <= expected.fetch(:age_gyr_max, age)
    metallicity_ok = z >= expected.fetch(:metallicity_z_min, z) && z <= expected.fetch(:metallicity_z_max, z)
    allowed_sfh = Array(expected[:sfh_models]).map(&:to_s)
    sfh_ok = allowed_sfh.empty? || allowed_sfh.include?(sfh)

    checks = {
      age_ok: age_ok,
      metallicity_ok: metallicity_ok,
      sfh_ok: sfh_ok
    }

    score = checks.values.count(true)
    verdict = if score == checks.size
      "pass"
    elsif score.zero?
      "fail"
    else
      "warn"
    end

    { verdict: verdict, checks: checks }
  end

  def elapsed_seconds(started_at)
    return nil unless started_at

    [(Time.current - started_at).round, 0].max
  end
end
