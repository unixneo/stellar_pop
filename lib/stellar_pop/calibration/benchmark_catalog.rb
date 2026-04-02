module StellarPop
  module Calibration
    class BenchmarkCatalog
      class << self
        def all(sdss_release: nil)
          new(sdss_release: sdss_release).benchmarks
        end
      end

      def initialize(sdss_release: nil)
        @sdss_release = sdss_release.to_s.upcase.presence
      end

      def benchmarks
        scope = Galaxy.usable_photometry.includes(:galaxy_photometry, :galaxy_spectroscopies).order(:name)
        scope = scope.where(sdss_dr: @sdss_release) if @sdss_release.present?

        scope.filter_map do |galaxy|
          observations = observations_for_galaxy(galaxy)
          next if observations.empty?

          age_avg, age_count = numeric_avg_and_count(observations, :age_gyr)
          metallicity_avg, metallicity_count = numeric_avg_and_count(observations, :metallicity_z)
          stellar_mass_avg, stellar_mass_count = numeric_avg_and_count(observations, :stellar_mass)

          {
            key: galaxy.name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, ""),
            name: galaxy.name,
            type: galaxy.galaxy_type,
            benchmark_type: benchmark_type_for(observations),
            ra: galaxy.ra,
            dec: galaxy.dec,
            photometry: galaxy.photometry_hash,
            data_quality: build_data_quality(galaxy),
            expected: {
              age_gyr_min: age_avg,
              age_gyr_max: age_avg,
              metallicity_z_min: metallicity_avg,
              metallicity_z_max: metallicity_avg,
              stellar_mass_min: stellar_mass_avg,
              stellar_mass_max: stellar_mass_avg,
              observation_counts: {
                age_gyr: age_count,
                metallicity_z: metallicity_count,
                stellar_mass: stellar_mass_count
              },
              aggregation_note: aggregation_note(age_count, metallicity_count, stellar_mass_count),
              sfh_models: []
            },
            notes: observations.map(&:notes).map(&:to_s).reject(&:empty?).uniq.join(" "),
            references: observations.map(&:source_paper).map(&:to_s).reject(&:empty?).uniq
          }
        end
      end

      private

      def observations_for_galaxy(galaxy)
        sdss_objid = galaxy.sdss_objid.to_s.strip
        return [] if sdss_objid.empty?

        Observation.where(sdss_objid: sdss_objid).order(:id).to_a
      end

      def benchmark_type_for(observations)
        observations.map(&:method_used).map(&:to_s).reject(&:empty?).first || "db_observation"
      end

      def build_data_quality(galaxy)
        phot = galaxy.preferred_photometry
        spec = galaxy.preferred_spectroscopy
        bands = %i[u g r i z]
        errors = galaxy.photometry_errors_hash
        has_band_errors = bands.all? { |band| !errors[band].nil? }
        has_redshift_error = !spec&.z_err.nil?
        id_quality = phot&.id_match_quality.to_s
        redshift_conf = spec&.redshift_confidence.to_s

        reasons = []
        reasons << "id_match_quality=#{id_quality}" unless id_quality == "exact_objid"
        reasons << "redshift_confidence=#{redshift_conf}" unless redshift_conf == "high"
        reasons << "missing_band_errors" unless has_band_errors
        reasons << "missing_redshift_error" unless has_redshift_error

        {
          id_match_quality: id_quality,
          id_match_distance_arcsec: phot&.id_match_distance_arcsec,
          redshift_source: spec&.redshift_source,
          redshift_confidence: redshift_conf,
          has_band_errors: has_band_errors,
          has_redshift_error: has_redshift_error,
          benchmark_eligible: reasons.empty?,
          reasons: reasons
        }
      end

      def numeric_values(observations, field)
        observations.map { |obs| obs.public_send(field) }.compact.map(&:to_f)
      end

      def numeric_min(observations, field)
        numeric_avg(observations, field)
      end

      def numeric_max(observations, field)
        numeric_avg(observations, field)
      end

      def numeric_avg(observations, field)
        avg, = numeric_avg_and_count(observations, field)
        avg
      end

      def numeric_avg_and_count(observations, field)
        values = numeric_values(observations, field)
        return [nil, 0] if values.empty?

        [(values.sum / values.length.to_f), values.length]
      end

      def aggregation_note(age_count, metallicity_count, stellar_mass_count)
        multi = []
        multi << "age_gyr=#{age_count}" if age_count > 1
        multi << "metallicity_z=#{metallicity_count}" if metallicity_count > 1
        multi << "stellar_mass=#{stellar_mass_count}" if stellar_mass_count > 1
        return "Single literature value per observable (matched by SDSS ObjID)." if multi.empty?

        "Averaged multiple literature values by SDSS ObjID for: #{multi.join(', ')}."
      end
    end
  end
end
