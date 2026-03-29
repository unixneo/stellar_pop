module StellarPop
  module KnowledgeSources
    class ImfSampler
      MASS_MIN = 0.1
      MASS_MAX = 150.0
      CHABRIER_MASS_MIN = 0.1
      CHABRIER_MASS_MAX = 100.0

      SEGMENTS = [
        { min: 0.1, max: 0.5, slope: -1.3, coeff: 1.0 },
        { min: 0.5, max: 1.0, slope: -2.3, coeff: 0.5 },
        { min: 1.0, max: 150.0, slope: -2.3, coeff: 0.5 }
      ].freeze
      SALPETER_SEGMENTS = [
        { min: 0.1, max: 150.0, slope: -2.35, coeff: 1.0 }
      ].freeze
      CHABRIER_LOG_MEAN = Math.log10(0.079).freeze
      CHABRIER_LOG_SIGMA = 0.69
      CHABRIER_HIGH_MASS_SLOPE = -2.3

      SPECTRAL_TYPE_BOUNDS = {
        "O" => 16.0..Float::INFINITY,
        "B" => 2.1...16.0,
        "A" => 1.4...2.1,
        "F" => 1.04...1.4,
        "G" => 0.8...1.04,
        "K" => 0.45...0.8,
        "M" => 0.08...0.45
      }.freeze

      def initialize(seed: nil, imf_type: :kroupa)
        @random = seed.nil? ? Random.new : Random.new(seed)
        @last_sample = nil
        @imf_type = normalize_imf_type(imf_type)
        if @imf_type == :chabrier
          @segments = []
          @normalized_segments = []
          @chabrier_high_mass_coeff = chabrier_lognormal_density(1.0)
          @chabrier_density_max = compute_chabrier_density_max
        else
          @segments = select_segments(@imf_type)
          @normalized_segments = build_normalized_segments
        end
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

      def spectral_type_for_mass(mass)
        classify_mass(mass.to_f)
      end

      private

      def build_normalized_segments
        total_weight = @segments.sum { |segment| segment[:coeff] * integral_power_law(segment) }
        cumulative = 0.0

        @segments.map do |segment|
          weight = (segment[:coeff] * integral_power_law(segment)) / total_weight
          cumulative += weight
          segment.merge(probability: weight, cumulative_probability: cumulative)
        end
      end

      def select_segments(imf_type)
        type = imf_type.to_sym
        return SEGMENTS if type == :kroupa
        return SALPETER_SEGMENTS if type == :salpeter

        raise ArgumentError, "imf_type must be :kroupa, :salpeter, or :chabrier"
      end

      def normalize_imf_type(imf_type)
        type = imf_type.to_sym
        return type if %i[kroupa salpeter chabrier].include?(type)

        raise ArgumentError, "imf_type must be :kroupa, :salpeter, or :chabrier"
      end

      def draw_mass
        return draw_chabrier_mass if @imf_type == :chabrier

        segment = choose_segment
        inverse_sample(segment[:min], segment[:max], segment[:slope], @random.rand)
      end

      def draw_chabrier_mass
        loop do
          candidate = CHABRIER_MASS_MIN + @random.rand * (CHABRIER_MASS_MAX - CHABRIER_MASS_MIN)
          acceptance = chabrier_density(candidate) / @chabrier_density_max
          return candidate if @random.rand <= acceptance
        end
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

      def chabrier_density(mass)
        return 0.0 if mass < CHABRIER_MASS_MIN || mass > CHABRIER_MASS_MAX

        if mass < 1.0
          chabrier_lognormal_density(mass)
        else
          @chabrier_high_mass_coeff * (mass**CHABRIER_HIGH_MASS_SLOPE)
        end
      end

      def chabrier_lognormal_density(mass)
        log_mass = Math.log10(mass)
        exponent = -((log_mass - CHABRIER_LOG_MEAN)**2) / (2.0 * (CHABRIER_LOG_SIGMA**2))
        Math.exp(exponent)
      end

      def compute_chabrier_density_max
        samples = 10_000
        max_density = 0.0
        step = (CHABRIER_MASS_MAX - CHABRIER_MASS_MIN) / samples.to_f
        mass = CHABRIER_MASS_MIN

        (samples + 1).times do
          density = chabrier_density(mass)
          max_density = density if density > max_density
          mass += step
        end

        max_density
      end

      def classify_mass(mass)
        SPECTRAL_TYPE_BOUNDS.find { |_type, range| range.cover?(mass) }&.first
      end
    end
  end
end
