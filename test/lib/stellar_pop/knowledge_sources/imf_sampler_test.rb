require "test_helper"

class ImfSamplerTest < ActiveSupport::TestCase
  test "sample is reproducible with seed" do
    a = StellarPop::KnowledgeSources::ImfSampler.new(seed: 123)
    b = StellarPop::KnowledgeSources::ImfSampler.new(seed: 123)

    assert_equal a.sample(20), b.sample(20)
  end

  test "sample values stay within configured mass range" do
    sampler = StellarPop::KnowledgeSources::ImfSampler.new(seed: 42)

    masses = sampler.sample(200)

    assert masses.all? { |m| m >= StellarPop::KnowledgeSources::ImfSampler::MASS_MIN }
    assert masses.all? { |m| m <= StellarPop::KnowledgeSources::ImfSampler::MASS_MAX }
  end

  test "count_by_type bins masses into OBAFGKM" do
    sampler = StellarPop::KnowledgeSources::ImfSampler.new
    masses = [20.0, 5.0, 1.8, 1.2, 0.9, 0.6, 0.2]

    counts = sampler.count_by_type(masses)

    assert_equal({ "O" => 1, "B" => 1, "A" => 1, "F" => 1, "G" => 1, "K" => 1, "M" => 1 }, counts)
  end

  test "count_by_type raises if no masses and no prior sample" do
    sampler = StellarPop::KnowledgeSources::ImfSampler.new

    assert_raises(ArgumentError) { sampler.count_by_type }
  end
end
