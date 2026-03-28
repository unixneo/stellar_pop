require "test_helper"

class SdssFilterConvolverTest < ActiveSupport::TestCase
  test "convolve returns filter-weighted mean flux" do
    convolver = StellarPop::SdssFilterConvolver.new
    spectrum = {}
    (300..1050).step(5) { |wl| spectrum[wl.to_f] = 2.0 }

    assert_in_delta 2.0, convolver.convolve(spectrum, :u), 1e-9
    assert_in_delta 2.0, convolver.convolve(spectrum, :g), 1e-9
    assert_in_delta 2.0, convolver.convolve(spectrum, :r), 1e-9
    assert_in_delta 2.0, convolver.convolve(spectrum, :i), 1e-9
    assert_in_delta 2.0, convolver.convolve(spectrum, :z), 1e-9
  end

  test "convolve returns zero when filter range is outside spectrum coverage" do
    convolver = StellarPop::SdssFilterConvolver.new
    spectrum = {}
    (350..600).step(5) { |wl| spectrum[wl.to_f] = 1.0 }

    assert_equal 0.0, convolver.convolve(spectrum, :z)
  end

  test "synthetic_magnitudes returns all ugriz bands" do
    convolver = StellarPop::SdssFilterConvolver.new
    spectrum = {}
    (300..1050).step(5) { |wl| spectrum[wl.to_f] = 1.0 }

    mags = convolver.synthetic_magnitudes(spectrum)

    assert_equal %i[u g r i z], mags.keys
    assert mags.values.all? { |v| v.is_a?(Float) }
  end
end
