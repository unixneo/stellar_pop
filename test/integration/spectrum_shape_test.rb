require "test_helper"

class SpectrumShapeTest < ActiveSupport::TestCase
  test "composite spectrum has a physically plausible broad shape" do
    bb = StellarPop::Blackboard.new
    masses = StellarPop::KnowledgeSources::ImfSampler.new(seed: 42).sample(1000)
    ages = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0]
    sfh = StellarPop::KnowledgeSources::SfhModel.new

    bb.write(:imf_masses, masses)
    bb.write(:age_bins, ages)
    bb.write(:metallicity_z, 0.02)
    sfh_weights = sfh.weights(:exponential, ages, tau: 3.0)
    bb.write(:sfh_weights, sfh_weights)
    weighted_mean_age = ages.zip(sfh_weights).sum { |age, weight| age.to_f * weight.to_f } / sfh_weights.sum(&:to_f)
    bb.write(:age_gyr, weighted_mean_age)
    bb.write(:wavelength_range, 350.0..900.0)

    spectrum = StellarPop::Integrator::SpectralIntegrator.new(bb).run
    wavelengths = spectrum.keys.sort
    fluxes = wavelengths.map { |wl| spectrum[wl].to_f }

    assert_equal 111, wavelengths.size
    assert fluxes.all? { |f| f.finite? && f >= 0.0 }

    peak_flux, peak_index = fluxes.each_with_index.max
    peak_wavelength = wavelengths[peak_index]

    assert_in_delta 1.0, peak_flux, 1e-9
    assert_operator peak_index, :>, 8
    assert_operator peak_index, :<, wavelengths.length - 5
    assert_operator peak_wavelength, :>=, 400.0
    assert_operator peak_wavelength, :<=, 900.0

    left_mean = fluxes.first(10).sum / 10.0
    right_mean = fluxes.last(10).sum / 10.0
    edge_ratio = right_mean / [left_mean, 1e-12].max
    assert edge_ratio.finite?
    assert_operator edge_ratio, :>, 0.5
    assert_operator edge_ratio, :<, 1.5

    post_peak = fluxes[(peak_index + 1)..]
    negative_steps = post_peak.each_cons(2).count { |a, b| b < a }
    total_steps = [post_peak.length - 1, 1].max
    assert_operator negative_steps.to_f / total_steps, :>, 0.45
  end
end
