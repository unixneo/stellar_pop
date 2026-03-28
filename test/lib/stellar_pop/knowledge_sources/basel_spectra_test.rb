require "test_helper"

class BaselSpectraTest < ActiveSupport::TestCase
  test "maps metallicity to nearest BaSeL zlegend bin" do
    basel = StellarPop::KnowledgeSources::BaselSpectra.new
    assert_equal 0, basel.send(:metallicity_index, 0.0002)
    assert_equal 1, basel.send(:metallicity_index, 0.0007)
    assert_equal 4, basel.send(:metallicity_index, 0.02)
    assert_equal 5, basel.send(:metallicity_index, 0.08)
  end

  test "spectrum_for_mass accepts metallicity keyword and returns filtered nm spectrum" do
    basel = StellarPop::KnowledgeSources::BaselSpectra.new

    spectrum = basel.spectrum_for_mass(1.0, 350.0..900.0, metallicity_z: 0.0063)

    assert spectrum.any?
    assert spectrum.keys.all? { |wl| wl >= 350.0 && wl <= 900.0 }
    assert spectrum.values.all? { |f| f.finite? && f >= 0.0 && f <= 1e10 }
  end
end
