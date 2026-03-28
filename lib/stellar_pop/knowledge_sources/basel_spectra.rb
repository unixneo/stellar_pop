module StellarPop
  module KnowledgeSources
    class BaselSpectra
      GRID_DIR = File.expand_path("../../data/basel", __dir__).freeze
      LAMBDA_FILE = File.join(GRID_DIR, "basel.lambda").freeze
      LOGT_FILE = File.join(GRID_DIR, "basel_logt.dat").freeze
      LOGG_FILE = File.join(GRID_DIR, "basel_logg.dat").freeze
      SPECTRA_FILE = File.join(GRID_DIR, "basel_wlbc_z0.0200.spectra.bin").freeze

      EXPECTED_WAVELENGTH_COUNT = 1963
      EXPECTED_LOGT_COUNT = 68
      EXPECTED_LOGG_COUNT = 19
      EXPECTED_METALLICITY_COUNT = 6
      SOLAR_METALLICITY_INDEX = 4

      def initialize
        @wavelengths_angstrom = parse_text_floats(LAMBDA_FILE)
        @logt_grid = parse_text_floats(LOGT_FILE)
        @logg_grid = parse_text_floats(LOGG_FILE)

        validate_grid_sizes!
        @spectra_grid, @metallicity_count = load_spectra_grid
      end

      def spectrum(teff_k, logg, wavelength_range_nm = 91.0..10_000.0)
        raise ArgumentError, "teff_k must be > 0" unless teff_k.to_f.positive?

        target_logt = Math.log10(teff_k.to_f)
        teff_index = nearest_index(@logt_grid, target_logt)
        logg_index = nearest_index(@logg_grid, logg.to_f)

        start_index =
          (logg_index * (EXPECTED_LOGT_COUNT * @metallicity_count * EXPECTED_WAVELENGTH_COUNT)) +
          (teff_index * (@metallicity_count * EXPECTED_WAVELENGTH_COUNT)) +
          (metallicity_index * EXPECTED_WAVELENGTH_COUNT)
        flux_values = @spectra_grid[start_index, EXPECTED_WAVELENGTH_COUNT]

        result = {}
        @wavelengths_angstrom.each_with_index do |angstrom, i|
          wavelength_nm = angstrom / 10.0
          flux = flux_values[i]
          next unless wavelength_range_nm.cover?(wavelength_nm)
          next if flux.nil? || flux.nan? || !flux.finite? || flux.negative? || flux > 1e10

          result[wavelength_nm] = flux
        end
        result
      end

      def spectrum_for_mass(mass, wavelength_range_nm = 91.0..10_000.0)
        mass_value = mass.to_f
        raise ArgumentError, "mass must be > 0" unless mass_value.positive?

        teff_k = 5778.0 * (mass_value**0.54)
        logg = 4.44 + (Math.log10(mass_value) * 0.1)

        spectrum(teff_k, logg, wavelength_range_nm)
      end

      private

      def parse_text_floats(path)
        File.read(path).split.map(&:to_f)
      end

      def load_spectra_grid
        raw = File.binread(SPECTRA_FILE)
        floats = raw.unpack("g*")

        one_z_count = EXPECTED_LOGG_COUNT * EXPECTED_LOGT_COUNT * EXPECTED_WAVELENGTH_COUNT
        six_z_count = one_z_count * EXPECTED_METALLICITY_COUNT

        metallicity_count =
          if floats.length == six_z_count
            EXPECTED_METALLICITY_COUNT
          elsif floats.length == one_z_count
            1
          else
            raise "Unexpected spectra float count: #{floats.length} (expected #{one_z_count} or #{six_z_count})"
          end

        [floats, metallicity_count]
      end

      def metallicity_index
        return SOLAR_METALLICITY_INDEX if @metallicity_count >= EXPECTED_METALLICITY_COUNT

        0
      end

      def nearest_index(values, target)
        best_index = 0
        best_distance = Float::INFINITY

        values.each_with_index do |value, index|
          distance = (value - target).abs
          next unless distance < best_distance

          best_distance = distance
          best_index = index
        end

        best_index
      end

      def validate_grid_sizes!
        unless @wavelengths_angstrom.length == EXPECTED_WAVELENGTH_COUNT
          raise "Unexpected wavelength count: #{@wavelengths_angstrom.length} (expected #{EXPECTED_WAVELENGTH_COUNT})"
        end

        unless @logt_grid.length == EXPECTED_LOGT_COUNT
          raise "Unexpected logt count: #{@logt_grid.length} (expected #{EXPECTED_LOGT_COUNT})"
        end

        unless @logg_grid.length == EXPECTED_LOGG_COUNT
          raise "Unexpected logg count: #{@logg_grid.length} (expected #{EXPECTED_LOGG_COUNT})"
        end
      end
    end
  end
end
