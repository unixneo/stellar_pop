module StellarPop
  module KnowledgeSources
    class MistIsochrone
      DATA_PATH = File.expand_path("../../data/mist/isoc_zp0.00.dat", __dir__)
      SOLAR_METALLICITY = 0.02
      SOLAR_TEFF_K = 5778.0

      class << self
        attr_reader :log_ages, :rows_by_log_age

        def load_grid
          return if @log_ages && @rows_by_log_age

          rows_by_log_age = Hash.new { |hash, key| hash[key] = [] }

          File.foreach(DATA_PATH) do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#")

            fields = stripped.split
            next unless fields.length >= 9

            row = {
              log_age: fields[0].to_f,
              mini: fields[1].to_f,
              mact: fields[2].to_f,
              logl: fields[3].to_f,
              logt: fields[4].to_f,
              logg: fields[5].to_f,
              composition: fields[6].to_f,
              phase: fields[7].to_f,
              logmdot: fields[8].to_f
            }

            rows_by_log_age[row[:log_age]] << row
          end

          @rows_by_log_age = rows_by_log_age.transform_values { |rows| rows.sort_by { |r| r[:mini] } }
          @log_ages = @rows_by_log_age.keys.sort
        end
      end

      def initialize
        self.class.load_grid
      end

      def lookup(mass, age_gyr)
        validate_positive!(mass, "mass")
        validate_positive!(age_gyr, "age_gyr")

        target_log_age = Math.log10(age_gyr.to_f * 1_000_000_000.0)
        nearest_log_age = nearest_value(self.class.log_ages, target_log_age)
        rows = self.class.rows_by_log_age[nearest_log_age]
        return nil if rows.nil? || rows.empty?

        nearest_row = rows.min_by { |row| (row[:mini] - mass.to_f).abs }
        return nil unless nearest_row

        {
          teff_k: 10.0**nearest_row[:logt],
          luminosity_solar: 10.0**nearest_row[:logl],
          logg: nearest_row[:logg],
          phase: nearest_row[:phase]
        }
      end

      def validate_against_simple_isochrone
        simple_isochrone = StellarPop::KnowledgeSources::Isochrone.new
        masses = [0.5, 1.0, 2.0, 5.0, 10.0]
        ages = [1.0, 5.0, 10.0]

        masses.product(ages).map do |mass, age_gyr|
          mist = lookup(mass, age_gyr) || {}
          simple_teff = (SOLAR_TEFF_K * (mass.to_f**0.54)) + simple_isochrone.temperature_correction(mass, SOLAR_METALLICITY)

          {
            mass: mass,
            age: age_gyr,
            mist_teff: mist[:teff_k],
            simple_teff: simple_teff,
            mist_lum: mist[:luminosity_solar],
            simple_lum_correction: simple_isochrone.luminosity_correction(mass, age_gyr, SOLAR_METALLICITY)
          }
        end
      end

      private

      def nearest_value(values, target)
        values.min_by { |value| (value - target).abs }
      end

      def validate_positive!(value, name)
        raise ArgumentError, "#{name} must be > 0" unless value.to_f.positive?
      end
    end
  end
end
