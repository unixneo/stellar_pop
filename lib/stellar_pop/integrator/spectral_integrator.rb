module StellarPop
  module Integrator
    class SpectralIntegrator
      def initialize(blackboard, spectra_source: nil)
        @blackboard = blackboard
        @spectra_source = spectra_source || StellarPop::KnowledgeSources::BaselSpectra.new
      end

      def run
        masses = read_required(:imf_masses)
        sfh_weights = read_required(:sfh_weights)
        age_bins = read_required(:age_bins)
        age_gyr = read_required(:age_gyr).to_f
        metallicity_z = read_required(:metallicity_z).to_f
        wavelength_range = read_required(:wavelength_range)

        validate_inputs!(masses, sfh_weights, age_bins, age_gyr, metallicity_z, wavelength_range)

        imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new
        mist_isochrone = StellarPop::KnowledgeSources::MistIsochrone.new

        composite = {}
        star_contributions = []

        masses.each do |mass|
          mass_f = mass.to_f
          base_spectrum = build_base_spectrum(mass_f, wavelength_range, metallicity_z, imf_sampler)
          star_flux_sum = base_spectrum.values.sum.to_f
          next unless star_flux_sum.positive?

          mist_row = mist_isochrone.lookup(mass_f, age_gyr, metallicity_z: metallicity_z)
          mist_luminosity = mist_row && mist_row[:luminosity_solar].to_f
          raw_weight = if mist_luminosity&.positive?
            mist_luminosity
          else
            mass_f**1.0
          end
          next unless raw_weight.positive?

          star_contributions << {
            spectrum: base_spectrum,
            wavelengths: base_spectrum.keys.sort,
            flux_sum: star_flux_sum,
            raw_weight: raw_weight
          }
        end

        total_raw_weight = star_contributions.sum { |entry| entry[:raw_weight] }.to_f
        common_wavelength_grid = build_uniform_wavelength_grid(wavelength_range)

        if total_raw_weight.positive? && !common_wavelength_grid.empty?
          star_contributions.each do |entry|
            normalized_star_weight = entry[:raw_weight] / total_raw_weight

            common_wavelength_grid.each do |wavelength_nm|
              flux = interpolate_flux(entry[:spectrum], entry[:wavelengths], wavelength_nm)
              normalized_flux = flux / entry[:flux_sum]
              contribution = normalized_flux * normalized_star_weight
              composite[wavelength_nm] = composite.fetch(wavelength_nm, 0.0) + contribution
            end
          end
        end

        smooth_composite!(composite)
        normalize_peak!(composite)
        @blackboard.write(:composite_spectrum, composite)
        composite
      end

      private

      def read_required(key)
        value = @blackboard.read(key)
        raise ArgumentError, "missing blackboard key: #{key}" if value.nil?

        value
      end

      def validate_inputs!(masses, sfh_weights, age_bins, age_gyr, metallicity_z, wavelength_range)
        raise ArgumentError, "imf_masses must be a non-empty Array" unless masses.is_a?(Array) && !masses.empty?
        raise ArgumentError, "sfh_weights must be a non-empty Array" unless sfh_weights.is_a?(Array) && !sfh_weights.empty?
        raise ArgumentError, "age_bins must be a non-empty Array" unless age_bins.is_a?(Array) && !age_bins.empty?
        raise ArgumentError, "sfh_weights and age_bins must have the same length" unless sfh_weights.length == age_bins.length
        raise ArgumentError, "age_gyr must be > 0" unless age_gyr.positive?
        raise ArgumentError, "metallicity_z must be > 0" unless metallicity_z.positive?
        raise ArgumentError, "wavelength_range must be an inclusive Range" unless wavelength_range.is_a?(Range) && !wavelength_range.exclude_end?
      end

      def build_base_spectrum(mass_f, wavelength_range, metallicity_z, imf_sampler)
        if @spectra_source.respond_to?(:spectrum_for_mass)
          return @spectra_source.spectrum_for_mass(mass_f, wavelength_range, metallicity_z: metallicity_z)
        end

        spectral_type = imf_sampler.spectral_type_for_mass(mass_f)
        return {} unless spectral_type

        @spectra_source.spectrum(spectral_type, wavelength_range)
      end

      def build_uniform_wavelength_grid(wavelength_range)
        min_wavelength = wavelength_range.begin.to_f
        max_wavelength = wavelength_range.end.to_f
        grid = []

        wavelength = min_wavelength
        while wavelength <= max_wavelength
          grid << wavelength
          wavelength += 5.0
        end

        grid
      end

      def interpolate_flux(spectrum, sorted_wavelengths, target_wavelength)
        return 0.0 if sorted_wavelengths.empty?
        return 0.0 if target_wavelength < sorted_wavelengths.first || target_wavelength > sorted_wavelengths.last

        exact = spectrum[target_wavelength]
        return exact.to_f if exact

        upper_index = sorted_wavelengths.bsearch_index { |wl| wl >= target_wavelength }
        return 0.0 if upper_index.nil? || upper_index.zero?

        lower = sorted_wavelengths[upper_index - 1]
        upper = sorted_wavelengths[upper_index]
        return spectrum[lower].to_f if upper == lower

        lower_flux = spectrum[lower].to_f
        upper_flux = spectrum[upper].to_f
        fraction = (target_wavelength - lower) / (upper - lower)
        lower_flux + ((upper_flux - lower_flux) * fraction)
      end

      def smooth_composite!(spectrum)
        return spectrum if spectrum.empty?

        wavelengths = spectrum.keys.sort
        smoothed = {}

        wavelengths.each_with_index do |wavelength, index|
          window_start = [index - 5, 0].max
          window_end = [index + 5, wavelengths.length - 1].min
          window = wavelengths[window_start..window_end]
          mean_flux = window.sum { |wl| spectrum[wl].to_f } / window.length.to_f
          smoothed[wavelength] = mean_flux
        end

        smoothed.each do |wavelength, flux|
          spectrum[wavelength] = flux
        end

        spectrum
      end

      def normalize_peak!(spectrum)
        return spectrum if spectrum.empty?

        peak_flux = spectrum.values.max.to_f
        return spectrum unless peak_flux.positive?

        spectrum.each_key do |wavelength_nm|
          spectrum[wavelength_nm] /= peak_flux
        end
      end
    end
  end
end
