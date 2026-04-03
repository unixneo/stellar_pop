require "test_helper"

module StellarPop
  class StellarMassEstimatorTest < ActiveSupport::TestCase
    test "returns positive stellar mass for valid photometry and redshift" do
      mass = StellarMassEstimator.estimate(
        sfh_model: "exponential",
        imf_type: "kroupa",
        age_gyr: 8.0,
        observed_r_mag: 13.0,
        redshift_z: 0.01
      )

      assert mass.to_f.positive?
    end

    test "returns nil for non-positive redshift" do
      mass = StellarMassEstimator.estimate(
        sfh_model: "exponential",
        imf_type: "kroupa",
        age_gyr: 8.0,
        observed_r_mag: 13.0,
        redshift_z: 0.0
      )

      assert_nil mass
    end

    test "salpeter imf yields larger stellar mass than chabrier for same inputs" do
      salpeter_mass = StellarMassEstimator.estimate(
        sfh_model: "delayed_exponential",
        imf_type: "salpeter",
        age_gyr: 6.0,
        observed_r_mag: 13.5,
        redshift_z: 0.012
      )
      chabrier_mass = StellarMassEstimator.estimate(
        sfh_model: "delayed_exponential",
        imf_type: "chabrier",
        age_gyr: 6.0,
        observed_r_mag: 13.5,
        redshift_z: 0.012
      )

      assert salpeter_mass > chabrier_mass
    end

    test "mass log offset scales stellar mass by 10^dex" do
      baseline = StellarMassEstimator.estimate(
        sfh_model: "exponential",
        imf_type: "kroupa",
        age_gyr: 10.0,
        observed_r_mag: 13.0,
        redshift_z: 0.01,
        mass_log_offset_dex: 0.0
      )
      adjusted = StellarMassEstimator.estimate(
        sfh_model: "exponential",
        imf_type: "kroupa",
        age_gyr: 10.0,
        observed_r_mag: 13.0,
        redshift_z: 0.01,
        mass_log_offset_dex: 0.1
      )

      expected_scale = 10.0**0.1
      assert_in_delta baseline * expected_scale, adjusted, baseline * 1.0e-9
    end
  end
end
