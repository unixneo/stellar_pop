require "test_helper"

class BenchmarkRunJobTest < ActiveSupport::TestCase
  test "evaluate_best_fit fails when chi-squared exceeds validation threshold" do
    job = BenchmarkRunJob.new
    best = { age_gyr: 10.0, metallicity_z: 0.02, sfh_model: "exponential", chi_squared: 0.45 }
    benchmark = {
      expected: {
        age_gyr_min: 8.0,
        age_gyr_max: 12.0,
        metallicity_z_min: 0.01,
        metallicity_z_max: 0.03,
        sfh_models: ["exponential", "burst"]
      }
    }

    evaluation = job.send(:evaluate_best_fit, best, benchmark)

    assert_equal "fail", evaluation[:verdict]
    assert_equal false, evaluation[:checks][:chi_squared_ok]
  end
end
