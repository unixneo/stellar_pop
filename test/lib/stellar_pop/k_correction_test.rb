require "test_helper"

class KCorrectionTest < ActiveSupport::TestCase
  test "applies first-order correction for z between 0 and 0.1" do
    mags = { u: 15.0, g: 14.5, r: 14.0, i: 13.8, z: 13.7 }

    corrected = StellarPop::KCorrection.correct(mags, 0.02)

    assert_not_equal mags, corrected
    assert_in_delta 14.97944, corrected[:u], 1e-6
    assert_in_delta 14.52984, corrected[:g], 1e-6
    assert_in_delta 14.01054, corrected[:r], 1e-6
    assert_in_delta 13.80592, corrected[:i], 1e-6
    assert_in_delta 13.70263, corrected[:z], 1e-6
  end

  test "returns unchanged magnitudes for zero redshift" do
    mags = { u: 15.0, g: 14.5, r: 14.0, i: 13.8, z: 13.7 }

    corrected = StellarPop::KCorrection.correct(mags, 0.0)

    assert_equal mags, corrected
  end
end
