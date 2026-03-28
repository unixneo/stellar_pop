require "test_helper"

class StellarSpectraTest < ActiveSupport::TestCase
  test "planck returns positive radiance for valid inputs" do
    spectra = StellarPop::KnowledgeSources::StellarSpectra.new

    value = spectra.planck(550.0, 5778.0)

    assert value.positive?
  end

  test "planck validates wavelength and temperature" do
    spectra = StellarPop::KnowledgeSources::StellarSpectra.new

    assert_raises(ArgumentError) { spectra.planck(0.0, 5778.0) }
    assert_raises(ArgumentError) { spectra.planck(550.0, 0.0) }
  end

  test "spectrum returns inclusive 10nm grid" do
    spectra = StellarPop::KnowledgeSources::StellarSpectra.new

    result = spectra.spectrum("G", 400.0..430.0)

    assert_equal [400.0, 410.0, 420.0, 430.0], result.keys
    assert result.values.all?(&:positive?)
  end

  test "spectrum raises for unknown spectral type" do
    spectra = StellarPop::KnowledgeSources::StellarSpectra.new

    assert_raises(ArgumentError) { spectra.spectrum("X", 400.0..430.0) }
  end
end
