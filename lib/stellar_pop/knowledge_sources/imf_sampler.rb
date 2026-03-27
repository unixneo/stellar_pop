module StellarPop
  module KnowledgeSources
    class ImfSampler
      MASS_MIN = 0.1
      MASS_MAX = 150.0

      SEGMENTS = [
        { min: 0.1, max: 0.5, slope: -1.3, coeff: 1.0 },
        { min: 0.5, max: 1.0, slope: -2.3, coeff: 0.5 },
        { min: 1.0, max: 150.0, slope: -2.3, coeff: 0.5 }
      ].freeze

      SPECTRAL_TYPE_BOUNDS = {
        "O" => 16.0..Float::INFINITY,
        "B" => 2.1...16.0,
        "A" => 1.4...2.1,
        "F" => 1.04...1.4,
        "G" => 0.8...1.04,
        "K" => 0.45...0.8,
        "M" => 0.08...0.45
      }.freeze

      def initialize(seed: nil)
        @random = Random.new(seed)
        @last_sample = nil
        @normalized_segments = build_normalized_segments
      end

      def sample(n)
        raise ArgumentError, "n must be a positive integer" unless n.is_a?(Integer) && n.positive?

        @last_sample = Array.new(n) { draw_mass }
      end

      def count_by_type(masses = nil)
        masses ||= @last_sample
        raise ArgumentError, "provide masses or call sample first" unless masses

        counts = SPECTRAL_TYPE_BOUNDS.keys.each_with_object({}) { |type, h| h[type] = 0 }

        masses.each do |mass|
          type = classify_mass(mass)
          counts[type] += 1 if type
        end

        counts
      end

      private

      def build_normalized_segments
        total_weight = SEGMENTS.sum { |segment| segment[:coeff] * integral_power_law(segment) }
        cumulative = 0.0

        SEGMENTS.map do |segment|
          weight = (segment[:coeff] * integral_power_law(segment)) / total_weight
          cumulative += weight
          segment.merge(probability: weight, cumulative_probability: cumulative)
        end
      end

      def draw_mass
        segment = choose_segment
        inverse_sample(segment[:min], segment[:max], segment[:slope], @random.rand)
      end

      def choose_segment
        u = @random.rand
        @normalized_segments.find { |segment| u <= segment[:cumulative_probability] } || @normalized_segments.last
      end

      def integral_power_law(segment)
        slope = segment[:slope]
        lower = segment[:min]
        upper = segment[:max]
        exponent = slope + 1.0

        (upper**exponent - lower**exponent) / exponent
      end

      def inverse_sample(lower, upper, slope, u)
        exponent = slope + 1.0
        lower_term = lower**exponent
        upper_term = upper**exponent

        (lower_term + u * (upper_term - lower_term))**(1.0 / exponent)
      end

      def classify_mass(mass)
        SPECTRAL_TYPE_BOUNDS.find { |_type, range| range.cover?(mass) }&.first
      end
    end
  end
end
