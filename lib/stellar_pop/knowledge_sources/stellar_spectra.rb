module StellarPop
  module KnowledgeSources
    class StellarSpectra
      SPEED_OF_LIGHT = 299_792_458.0.freeze
      PLANCK_CONSTANT = 6.626_070_15e-34.freeze
      BOLTZMANN_CONSTANT = 1.380_649e-23.freeze
      NM_TO_M = 1e-9.freeze

      SPECTRAL_TYPE_TEMPERATURES = {
        "O" => 35_000.0,
        "B" => 20_000.0,
        "A" => 8_500.0,
        "F" => 6_700.0,
        "G" => 5_700.0,
        "K" => 4_500.0,
        "M" => 3_200.0
      }.freeze

      def planck(wavelength_nm, temp_k)
        wavelength_m = wavelength_nm.to_f * NM_TO_M
        raise ArgumentError, "wavelength_nm must be > 0" unless wavelength_m.positive?
        raise ArgumentError, "temp_k must be > 0" unless temp_k.to_f.positive?

        numerator = 2.0 * Math::PI * PLANCK_CONSTANT * SPEED_OF_LIGHT**2
        exponent = (PLANCK_CONSTANT * SPEED_OF_LIGHT) / (wavelength_m * BOLTZMANN_CONSTANT * temp_k.to_f)
        denominator = (wavelength_m**5) * (Math.exp(exponent) - 1.0)
        numerator / denominator
      end

      def spectrum(type, wavelength_range)
        spectral_type = type.to_s.upcase
        temp_k = SPECTRAL_TYPE_TEMPERATURES[spectral_type]
        raise ArgumentError, "unknown spectral type: #{type}" unless temp_k

        range = normalize_range(wavelength_range)
        flux = {}

        wavelength = range.begin.to_f
        while wavelength <= range.end.to_f
          flux[wavelength] = planck(wavelength, temp_k)
          wavelength += 10.0
        end

        flux
      end

      private

      def normalize_range(wavelength_range)
        unless wavelength_range.is_a?(Range) && !wavelength_range.exclude_end?
          raise ArgumentError, "wavelength_range must be an inclusive Range"
        end

        min_nm = wavelength_range.begin.to_f
        max_nm = wavelength_range.end.to_f

        raise ArgumentError, "range bounds must be > 0" unless min_nm.positive? && max_nm.positive?
        raise ArgumentError, "range end must be >= range begin" if max_nm < min_nm

        (min_nm..max_nm)
      end
    end
  end
end
