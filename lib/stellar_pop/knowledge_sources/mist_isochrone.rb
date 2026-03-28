module StellarPop
  module KnowledgeSources
    class MistIsochrone
      DATA_GLOB = File.expand_path("../../data/mist/isoc_z*.dat", __dir__)
      SOLAR_Z_ASPLUND_2009 = 0.0142
      SOLAR_METALLICITY = 0.02
      SOLAR_TEFF_K = 5778.0
      FEH_BY_LABEL = {
        "zm2.50" => -2.50,
        "zm2.00" => -2.00,
        "zm1.75" => -1.75,
        "zm1.50" => -1.50,
        "zm1.25" => -1.25,
        "zm1.00" => -1.00,
        "zm0.75" => -0.75,
        "zm0.50" => -0.50,
        "zm0.25" => -0.25,
        "zp0.00" => 0.00,
        "zp0.25" => 0.25,
        "zp0.50" => 0.50
      }.freeze

      class << self
        attr_reader :feh_values, :grid_by_feh

        def metallicity_to_feh(metallicity_z)
          Math.log10(metallicity_z.to_f / SOLAR_Z_ASPLUND_2009)
        end

        def nearest_feh_for_metallicity(metallicity_z)
          load_grid
          feh = metallicity_to_feh(metallicity_z.to_f)
          return nil if @feh_values.nil? || @feh_values.empty?

          @feh_values.min_by { |value| (value - feh).abs }
        end

        def load_grid
          return if @feh_values && @grid_by_feh

          grid_by_feh = {}
          Dir.glob(DATA_GLOB).sort.each do |path|
            label = File.basename(path)[/isoc_(z[mp]\d+\.\d+)\.dat/, 1]
            next unless label

            feh = FEH_BY_LABEL[label]
            next if feh.nil?

            rows_by_log_age = Hash.new { |hash, key| hash[key] = [] }
            File.foreach(path) do |line|
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

            grid_by_feh[feh] = {
              log_ages: rows_by_log_age.keys.sort,
              rows_by_log_age: rows_by_log_age.transform_values { |rows| rows.sort_by { |r| r[:mini] } }
            }
          end

          @grid_by_feh = grid_by_feh
          @feh_values = grid_by_feh.keys.sort
        end
      end

      def initialize
        self.class.load_grid
      end

      def lookup(mass, age_gyr, metallicity_z: 0.02)
        validate_positive!(mass, "mass")
        validate_positive!(age_gyr, "age_gyr")
        validate_positive!(metallicity_z, "metallicity_z")

        nearest_feh = self.class.nearest_feh_for_metallicity(metallicity_z.to_f)
        selected_grid = self.class.grid_by_feh[nearest_feh]
        return nil unless selected_grid

        log_ages = selected_grid[:log_ages]
        rows_by_log_age = selected_grid[:rows_by_log_age]
        target_log_age = Math.log10(age_gyr.to_f * 1_000_000_000.0)
        nearest_log_age = nearest_value(log_ages, target_log_age)
        rows = rows_by_log_age[nearest_log_age]
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
          mist = lookup(mass, age_gyr, metallicity_z: SOLAR_METALLICITY) || {}
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
        return nil if values.nil? || values.empty?

        values.min_by { |value| (value - target).abs }
      end

      def validate_positive!(value, name)
        raise ArgumentError, "#{name} must be > 0" unless value.to_f.positive?
      end
    end
  end
end
