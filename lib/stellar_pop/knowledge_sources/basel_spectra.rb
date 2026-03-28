module StellarPop
  module KnowledgeSources
    class BaselSpectra
      GRID_DIR = File.expand_path("../../data/basel", __dir__).freeze
      LAMBDA_FILE = File.join(GRID_DIR, "basel.lambda").freeze
      LOGT_FILE = File.join(GRID_DIR, "basel_logt.dat").freeze
      LOGG_FILE = File.join(GRID_DIR, "basel_logg.dat").freeze
      ZLEGEND_FILE = File.join(GRID_DIR, "zlegend.dat").freeze
      SPECTRA_FILE = File.join(GRID_DIR, "basel_wlbc_z0.0200.spectra.bin").freeze
      SPECTRA_FILE_BY_Z = {
        0.0002 => File.join(GRID_DIR, "basel_wlbc_z0.0002.spectra.bin").freeze,
        0.0006 => File.join(GRID_DIR, "basel_wlbc_z0.0006.spectra.bin").freeze,
        0.0020 => File.join(GRID_DIR, "basel_wlbc_z0.0020.spectra.bin").freeze,
        0.0063 => File.join(GRID_DIR, "basel_wlbc_z0.0063.spectra.bin").freeze,
        0.0200 => File.join(GRID_DIR, "basel_wlbc_z0.0200.spectra.bin").freeze,
        0.0632 => File.join(GRID_DIR, "basel_wlbc_z0.0632.spectra.bin").freeze
      }.freeze

      EXPECTED_WAVELENGTH_COUNT = 1963
      EXPECTED_LOGT_COUNT = 68
      EXPECTED_LOGG_COUNT = 19
      EXPECTED_METALLICITY_COUNT = 6
      ZLEGEND_VALUES = [0.0002, 0.0006, 0.0020, 0.0063, 0.0200, 0.0632].freeze
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
          validate_metallicity_grid!(metallicity_grid)
          all_fluxes, metallicity_count, fluxes_by_z = load_spectra_grid(metallicity_grid)

          @wavelengths = wavelengths
          @logt_grid = logt_grid
          @logg_grid = logg_grid
          @metallicity_grid = metallicity_grid
          @all_fluxes = all_fluxes
          @metallicity_count = metallicity_count
          @fluxes_by_z = fluxes_by_z
        end

        private

        def parse_text_floats(path)
          File.read(path).split.map(&:to_f)
        end

        def load_spectra_grid(metallicity_grid)
          raw = File.binread(SPECTRA_FILE)
          floats = raw.unpack("g*")

          one_z_count = EXPECTED_LOGG_COUNT * EXPECTED_LOGT_COUNT * EXPECTED_WAVELENGTH_COUNT
          expected_count = EXPECTED_LOGG_COUNT * EXPECTED_LOGT_COUNT * EXPECTED_METALLICITY_COUNT * EXPECTED_WAVELENGTH_COUNT
          if floats.length == expected_count
            return [floats, EXPECTED_METALLICITY_COUNT, nil]
          end

          unless floats.length == one_z_count
            raise "Unexpected spectra float count: #{floats.length} (expected #{one_z_count} or #{expected_count})"
          end

          fluxes_by_z = {}
          metallicity_grid.each do |z_value|
            path = SPECTRA_FILE_BY_Z[z_value]
            raise "Missing BaSeL spectra file for z=#{z_value}" unless path && File.exist?(path)

            z_floats = File.binread(path).unpack("g*")
            unless z_floats.length == one_z_count
              raise "Unexpected spectra float count for z=#{z_value}: #{z_floats.length} (expected #{one_z_count})"
            end

            fluxes_by_z[z_value] = z_floats
          end

          [floats, 1, fluxes_by_z]
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

        def validate_metallicity_grid!(metallicity_grid)
          unless metallicity_grid.length == EXPECTED_METALLICITY_COUNT
            raise "Unexpected metallicity count: #{metallicity_grid.length} (expected #{EXPECTED_METALLICITY_COUNT})"
          end

          metallicity_grid.each_with_index do |value, index|
            expected = ZLEGEND_VALUES[index]
            next if (value - expected).abs < 1e-6

            raise "Unexpected zlegend value at index #{index}: #{value} (expected #{expected})"
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
        @fluxes_by_z = self.class.instance_variable_get(:@fluxes_by_z)
      end

      def spectrum(teff_k, logg, wavelength_range_nm = 91.0..10_000.0, metallicity_z: SOLAR_METALLICITY_Z)
        raise ArgumentError, "teff_k must be > 0" unless teff_k.to_f.positive?

        target_logt = Math.log10(teff_k.to_f)
        teff_index = nearest_index(@logt_grid, target_logt)
        logg_index = nearest_index(@logg_grid, logg.to_f)
        z_index = metallicity_index(metallicity_z)

        flux_values = extract_flux_values(teff_index, logg_index, z_index)

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

      def extract_flux_values(teff_index, logg_index, z_index)
        if @metallicity_count == EXPECTED_METALLICITY_COUNT
          start_index =
            (logg_index * (EXPECTED_LOGT_COUNT * EXPECTED_METALLICITY_COUNT * EXPECTED_WAVELENGTH_COUNT)) +
            (teff_index * (EXPECTED_METALLICITY_COUNT * EXPECTED_WAVELENGTH_COUNT)) +
            (z_index * EXPECTED_WAVELENGTH_COUNT)
          return @spectra_grid[start_index, EXPECTED_WAVELENGTH_COUNT]
        end

        z_value = @metallicity_grid[z_index]
        plane = (@fluxes_by_z && @fluxes_by_z[z_value]) || @spectra_grid
        start_index = (logg_index * (EXPECTED_LOGT_COUNT * EXPECTED_WAVELENGTH_COUNT)) + (teff_index * EXPECTED_WAVELENGTH_COUNT)
        plane[start_index, EXPECTED_WAVELENGTH_COUNT]
      end

      def metallicity_index(metallicity_z)
        return SOLAR_METALLICITY_INDEX if @metallicity_grid.nil? || @metallicity_grid.empty?

        target = metallicity_z.to_f
        nearest_index(@metallicity_grid, target)
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
