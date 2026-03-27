module StellarPop
  module KnowledgeSources
    class Isochrone
      SOLAR_METALLICITY = 0.02
      BASE_MAIN_SEQUENCE_LIFETIME_GYR = 10.0

      def luminosity_correction(mass, age_gyr, metallicity_z)
        validate_positive!(mass, "mass")
        validate_non_negative!(age_gyr, "age_gyr")
        validate_positive!(metallicity_z, "metallicity_z")

        t_ms = BASE_MAIN_SEQUENCE_LIFETIME_GYR * (mass.to_f**-2.5)
        return giant_correction(mass) if age_gyr.to_f > t_ms

        1.0
      end

      def temperature_correction(mass, metallicity_z)
        validate_positive!(mass, "mass")
        validate_positive!(metallicity_z, "metallicity_z")

        -1000.0 * ((metallicity_z.to_f - SOLAR_METALLICITY) / SOLAR_METALLICITY)
      end

      private

      def giant_correction(mass)
        m = mass.to_f
        return 2.0 if m < 0.8
        return 8.0 if m < 1.5
        return 20.0 if m < 3.0

        50.0
      end

      def validate_positive!(value, name)
        raise ArgumentError, "#{name} must be > 0" unless value.to_f.positive?
      end

      def validate_non_negative!(value, name)
        raise ArgumentError, "#{name} must be >= 0" unless value.to_f >= 0.0
      end
    end
  end
end
