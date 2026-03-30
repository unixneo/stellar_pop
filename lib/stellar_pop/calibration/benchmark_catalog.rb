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
        scope = Galaxy.includes(:observations).order(:name)
        scope = scope.where(sdss_dr: @sdss_release) if @sdss_release.present?

        scope.filter_map do |galaxy|
          observations = galaxy.observations.to_a
          next if observations.empty?

          {
            key: galaxy.name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, ""),
            name: galaxy.name,
            type: galaxy.galaxy_type,
            benchmark_type: benchmark_type_for(observations),
            ra: galaxy.ra,
            dec: galaxy.dec,
            photometry: {
              u: galaxy.mag_u,
              g: galaxy.mag_g,
              r: galaxy.mag_r,
              i: galaxy.mag_i,
              z: galaxy.mag_z,
              redshift_z: galaxy.redshift_z
            },
            expected: {
              age_gyr_min: numeric_min(observations, :age_gyr),
              age_gyr_max: numeric_max(observations, :age_gyr),
              metallicity_z_min: numeric_min(observations, :metallicity_z),
              metallicity_z_max: numeric_max(observations, :metallicity_z),
              stellar_mass_min: numeric_min(observations, :stellar_mass),
              stellar_mass_max: numeric_max(observations, :stellar_mass),
              sfh_models: []
            },
            notes: observations.map(&:notes).map(&:to_s).reject(&:empty?).uniq.join(" "),
            references: observations.map(&:source_paper).map(&:to_s).reject(&:empty?).uniq
          }
        end
      end

      private

      def benchmark_type_for(observations)
        observations.map(&:method_used).map(&:to_s).reject(&:empty?).first || "db_observation"
      end

      def numeric_values(observations, field)
        observations.map { |obs| obs.public_send(field) }.compact.map(&:to_f)
      end

      def numeric_min(observations, field)
        values = numeric_values(observations, field)
        values.min unless values.empty?
      end

      def numeric_max(observations, field)
        values = numeric_values(observations, field)
        values.max unless values.empty?
      end
    end
  end
end
