require "test_helper"

class SfhModelTest < ActiveSupport::TestCase
  test "exponential_decay returns exp(-age/tau)" do
    sfh = StellarPop::KnowledgeSources::SfhModel.new

    assert_in_delta Math.exp(-2.0 / 4.0), sfh.exponential_decay(2.0, 4.0), 1e-12
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
    const = sfh.weights(:constant, ages, {})
    burst = sfh.weights(:burst, ages, burst_age_gyr: 3.0, width_gyr: 1.0)

    assert_in_delta 1.0, exp.sum, 1e-12
    assert_in_delta 1.0, const.sum, 1e-12
    assert_in_delta 1.0, burst.sum, 1e-12
  end
end
