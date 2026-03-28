require "test_helper"

class IsochroneTest < ActiveSupport::TestCase
  test "main-sequence stars return unity luminosity correction" do
    iso = StellarPop::KnowledgeSources::Isochrone.new

    assert_equal 1.0, iso.luminosity_correction(1.0, 5.0, 0.02)
  end

  test "post-main-sequence stars use giant correction capped at 10" do
    iso = StellarPop::KnowledgeSources::Isochrone.new

    assert_equal 10.0, iso.luminosity_correction(2.0, 20.0, 0.02)
  end

  test "temperature correction is zero at solar metallicity" do
    iso = StellarPop::KnowledgeSources::Isochrone.new

    assert_equal 0.0, iso.temperature_correction(1.0, 0.02)
  end

  test "temperature correction shifts cooler for higher metallicity" do
    iso = StellarPop::KnowledgeSources::Isochrone.new

    assert_operator iso.temperature_correction(1.0, 0.03), :<, 0.0
  end
end
