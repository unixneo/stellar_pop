module StellarPop
  module KnowledgeSources
    class BaselSpectra
      GRID_DIR = File.expand_path("../../data/basel", __dir__).freeze
      LAMBDA_FILE = File.join(GRID_DIR, "basel.lambda").freeze
      LOGT_FILE = File.join(GRID_DIR, "basel_logt.dat").freeze
      LOGG_FILE = File.join(GRID_DIR, "basel_logg.dat").freeze
      ZLEGEND_FILE = File.join(GRID_DIR, "zlegend.dat").freeze
      SPECTRA_FILE = File.join(GRID_DIR, "basel_wlbc_z0.0200.spectra.bin").freeze

      EXPECTED_WAVELENGTH_COUNT = 1963
      EXPECTED_LOGT_COUNT = 68
      EXPECTED_LOGG_COUNT = 19
      EXPECTED_METALLICITY_COUNT = 6
      SOLAR_METALLICITY_INDEX = 4
      SOLAR_METALLICITY_Z = 0.02

      class << self
        def load_grid
          return if @wavelengths && @logt_grid && @logg_grid && @all_fluxes

          wavelengths = parse_text_floats(LAMBDA_FILE)
          logt_grid = parse_text_floats(LOGT_FILE)
          logg_grid = parse_text_floats(LOGG_FILE)
          metallicity_grid = parse_text_floats(ZLEGEND_FILE)
          validate_grid_sizes!(wavelengths, logt_grid, logg_grid)
          all_fluxes, metallicity_count = load_spectra_grid

          @wavelengths = wavelengths
          @logt_grid = logt_grid
          @logg_grid = logg_grid
          @metallicity_grid = metallicity_grid
          @all_fluxes = all_fluxes
          @metallicity_count = metallicity_count
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

        def validate_grid_sizes!(wavelengths_angstrom, logt_grid, logg_grid)
          unless wavelengths_angstrom.length == EXPECTED_WAVELENGTH_COUNT
            raise "Unexpected wavelength count: #{wavelengths_angstrom.length} (expected #{EXPECTED_WAVELENGTH_COUNT})"
          end

          unless logt_grid.length == EXPECTED_LOGT_COUNT
            raise "Unexpected logt count: #{logt_grid.length} (expected #{EXPECTED_LOGT_COUNT})"
          end

          unless logg_grid.length == EXPECTED_LOGG_COUNT
            raise "Unexpected logg count: #{logg_grid.length} (expected #{EXPECTED_LOGG_COUNT})"
          end
        end
      end

      def initialize
        self.class.load_grid unless self.class.instance_variable_defined?(:@wavelengths)
        @wavelengths_angstrom = self.class.instance_variable_get(:@wavelengths)
        @logt_grid = self.class.instance_variable_get(:@logt_grid)
        @logg_grid = self.class.instance_variable_get(:@logg_grid)
        @metallicity_grid = self.class.instance_variable_get(:@metallicity_grid)
        @spectra_grid = self.class.instance_variable_get(:@all_fluxes)
        @metallicity_count = self.class.instance_variable_get(:@metallicity_count)
      end

      def spectrum(teff_k, logg, wavelength_range_nm = 91.0..10_000.0, metallicity_z: SOLAR_METALLICITY_Z)
        raise ArgumentError, "teff_k must be > 0" unless teff_k.to_f.positive?

        target_logt = Math.log10(teff_k.to_f)
        teff_index = nearest_index(@logt_grid, target_logt)
        logg_index = nearest_index(@logg_grid, logg.to_f)
        z_index = metallicity_index(metallicity_z)

        start_index =
          (logg_index * (EXPECTED_LOGT_COUNT * @metallicity_count * EXPECTED_WAVELENGTH_COUNT)) +
          (teff_index * (@metallicity_count * EXPECTED_WAVELENGTH_COUNT)) +
          (z_index * EXPECTED_WAVELENGTH_COUNT)
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

      def spectrum_for_mass(mass, wavelength_range_nm = 91.0..10_000.0, metallicity_z: SOLAR_METALLICITY_Z)
        mass_value = mass.to_f
        raise ArgumentError, "mass must be > 0" unless mass_value.positive?

        teff_k = 5778.0 * (mass_value**0.54)
        logg = 4.44 + (Math.log10(mass_value) * 0.1)

        spectrum(teff_k, logg, wavelength_range_nm, metallicity_z: metallicity_z)
      end

      private

      def metallicity_index(metallicity_z)
        return 0 if @metallicity_count <= 1
        return SOLAR_METALLICITY_INDEX if @metallicity_grid.nil? || @metallicity_grid.empty?

        target = metallicity_z.to_f
        nearest = nearest_index(@metallicity_grid, target)
        [nearest, @metallicity_count - 1].min
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
    end
  end
end
