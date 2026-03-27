module StellarPop
  module Integrator
    class SpectralIntegrator
      def initialize(blackboard)
        @blackboard = blackboard
      end

      def run
        masses = read_required(:imf_masses)
        sfh_weights = read_required(:sfh_weights)
        age_bins = read_required(:age_bins)
        metallicity_z = read_required(:metallicity_z).to_f
        wavelength_range = read_required(:wavelength_range)

        validate_inputs!(masses, sfh_weights, age_bins, metallicity_z, wavelength_range)

        imf_sampler = StellarPop::KnowledgeSources::ImfSampler.new
        stellar_spectra = StellarPop::KnowledgeSources::StellarSpectra.new
        isochrone = StellarPop::KnowledgeSources::Isochrone.new

        composite = {}
        star_contributions = []

        masses.each do |mass|
          mass_f = mass.to_f
          spectral_type = imf_sampler.spectral_type_for_mass(mass_f)
          next unless spectral_type

          base_spectrum = stellar_spectra.spectrum(spectral_type, wavelength_range)

          base_temp = StellarPop::KnowledgeSources::StellarSpectra::SPECTRAL_TYPE_TEMPERATURES[spectral_type]
          delta_temp = isochrone.temperature_correction(mass_f, metallicity_z)
          corrected_temp = [base_temp + delta_temp, 1.0].max

          corrected_spectrum = {}
          base_spectrum.each do |wavelength_nm, base_flux|
            base_planck = stellar_spectra.planck(wavelength_nm, base_temp)
            corrected_planck = stellar_spectra.planck(wavelength_nm, corrected_temp)
            temperature_factor = corrected_planck / base_planck

            corrected_spectrum[wavelength_nm] = base_flux * temperature_factor
          end

          star_flux_sum = corrected_spectrum.values.sum.to_f
          next unless star_flux_sum.positive?

          raw_weight = mass_f**1.0
          next unless raw_weight.positive?

          star_contributions << {
            spectrum: corrected_spectrum,
            flux_sum: star_flux_sum,
            raw_weight: raw_weight
          }
        end

        total_raw_weight = star_contributions.sum { |entry| entry[:raw_weight] }.to_f

        if total_raw_weight.positive?
          star_contributions.each do |entry|
            normalized_star_weight = entry[:raw_weight] / total_raw_weight

            entry[:spectrum].each do |wavelength_nm, corrected_flux|
              normalized_flux = corrected_flux / entry[:flux_sum]
              contribution = normalized_flux * normalized_star_weight
              composite[wavelength_nm] = composite.fetch(wavelength_nm, 0.0) + contribution
            end
          end
        end

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

      def validate_inputs!(masses, sfh_weights, age_bins, metallicity_z, wavelength_range)
        raise ArgumentError, "imf_masses must be a non-empty Array" unless masses.is_a?(Array) && !masses.empty?
        raise ArgumentError, "sfh_weights must be a non-empty Array" unless sfh_weights.is_a?(Array) && !sfh_weights.empty?
        raise ArgumentError, "age_bins must be a non-empty Array" unless age_bins.is_a?(Array) && !age_bins.empty?
        raise ArgumentError, "sfh_weights and age_bins must have the same length" unless sfh_weights.length == age_bins.length
        raise ArgumentError, "metallicity_z must be > 0" unless metallicity_z.positive?
        raise ArgumentError, "wavelength_range must be an inclusive Range" unless wavelength_range.is_a?(Range) && !wavelength_range.exclude_end?
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
