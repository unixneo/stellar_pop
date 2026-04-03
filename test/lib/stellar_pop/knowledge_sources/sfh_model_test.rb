require "test_helper"

class SfhModelTest < ActiveSupport::TestCase
  test "exponential_decay returns exp(-(total_age - stellar_age) / tau)" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new

    # stellar_age=2, total_age=10, tau=4 → lookback=8 → exp(-8/4) = exp(-2)
    assert_in_delta Math.exp(-2.0), sfh.exponential_decay(2.0, 4.0, 10.0), 1e-12
  end

  test "constant returns 1.0" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new

    assert_equal 1.0, sfh.constant(3.5)
  end

  test "burst peaks at burst age" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new

    center = sfh.burst(5.0, 5.0, 1.0)
    off_center = sfh.burst(7.0, 5.0, 1.0)

    assert_in_delta 1.0, center, 1e-12
    assert_operator off_center, :<, center
  end

  test "weights are normalized for each model" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    ages = [0.1, 1.0, 3.0, 8.0]

    exp = sfh.weights(:exponential, ages, tau: 3.0)
    delayed = sfh.weights(:delayed_exponential, ages, tau: 3.0)
    const = sfh.weights(:constant, ages, {})
    burst = sfh.weights(:burst, ages, burst_age_gyr: 3.0, width_gyr: 1.0)

    assert_in_delta 1.0, exp.sum, 1e-12
    assert_in_delta 1.0, delayed.sum, 1e-12
    assert_in_delta 1.0, const.sum, 1e-12
    assert_in_delta 1.0, burst.sum, 1e-12
  end

  test "delayed exponential peaks at intermediate age bin" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    ages = [0.1, 1.0, 3.0, 8.0, 12.0]
    weights = sfh.weights(:delayed_exponential, ages, tau: 3.0)

    assert_in_delta 1.0, weights.sum, 1e-12

    peak_index = weights.each_with_index.max_by { |weight, _idx| weight }.last
    assert_operator peak_index, :>, 0
    assert_operator peak_index, :<, ages.length - 1
  end

  test "burst weights peak at configured burst_age_gyr not youngest bin" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new
    ages = [0.1, 0.5, 1.0, 2.0, 4.0]
    weights = sfh.weights(:burst, ages, burst_age_gyr: 2.0, width_gyr: 0.5)

    assert_in_delta 1.0, weights.sum, 1e-12
    peak_index = weights.each_with_index.max_by { |weight, _idx| weight }.last

    assert_equal ages.index(2.0), peak_index
    refute_equal ages.index(0.1), peak_index
  end
end
