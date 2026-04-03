require "test_helper"

class SfhDistinguishabilityTest < ActiveSupport::TestCase
  def build_spectrum_for(model, tau:)
    bb = StellarPop::Blackboard.new
    masses = StellarPop::KnowledgeSources::ImfSampler.new(seed: 42).sample(400)
    age_bins = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0]
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    weights = sfh.weights(model, age_bins, tau: tau)

    bb.write(:imf_masses, masses)
    bb.write(:age_bins, age_bins)
    bb.write(:sfh_weights, weights)
    bb.write(:age_gyr, 12.0)
    bb.write(:metallicity_z, 0.02)
    bb.write(:wavelength_range, 350.0..900.0)

    StellarPop::Integrator::SpectralIntegrator.new(bb).run
  end

  test "exponential and delayed_exponential produce distinguishable spectra" do
    exponential = build_spectrum_for(:exponential, tau: 3.0)
    delayed = build_spectrum_for(:delayed_exponential, tau: 3.0)

    wavelengths = (exponential.keys & delayed.keys).sort
    assert wavelengths.any?, "expected overlapping wavelength grid"

    max_abs_delta = wavelengths.map { |wl| (exponential[wl].to_f - delayed[wl].to_f).abs }.max.to_f
    assert_operator max_abs_delta, :>, 1.0e-6
  end
end
