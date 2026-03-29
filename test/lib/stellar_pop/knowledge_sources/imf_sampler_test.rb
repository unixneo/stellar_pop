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

  test "salpeter produces lower high-mass fraction than kroupa" do
    sample_size = 20_000
    seed = 4242

    kroupa = StellarPop::KnowledgeSources::ImfSampler.new(seed: seed, imf_type: :kroupa).sample(sample_size)
    salpeter = StellarPop::KnowledgeSources::ImfSampler.new(seed: seed, imf_type: :salpeter).sample(sample_size)

    kroupa_above_one = kroupa.count { |m| m > 1.0 }.to_f / sample_size
    salpeter_above_one = salpeter.count { |m| m > 1.0 }.to_f / sample_size

    assert_operator salpeter_above_one, :<, kroupa_above_one
  end

  test "chabrier masses stay in 0.1..100 and distribution peaks below 1 solar mass" do
    sample_size = 20_000
    masses = StellarPop::KnowledgeSources::ImfSampler.new(seed: 9876, imf_type: :chabrier).sample(sample_size)

    assert masses.all? { |m| m >= 0.1 }
    assert masses.all? { |m| m <= 100.0 }

    below_one = masses.count { |m| m < 1.0 }.to_f / sample_size
    assert_operator below_one, :>, 0.5
  end
end
