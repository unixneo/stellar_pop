require "csv"

module StellarPop
  class SdssLocalCatalog
    CATALOG_PATH = File.expand_path("../data/sdss/photometry.csv", __dir__).freeze
    DEG_TO_RAD = Math::PI / 180.0
    RAD_TO_ARCMIN = (180.0 * 60.0) / Math::PI

    class << self
      def lookup(ra, dec, radius_arcmin: 1.0)
        target = lookup_target(ra, dec, radius_arcmin: radius_arcmin)
        return nil unless target

        {
          u: target[:u],
          g: target[:g],
          r: target[:r],
          i: target[:i],
          z: target[:z]
        }
      end

      def lookup_target(ra, dec, radius_arcmin: 1.0)
        target_ra = ra.to_f
        target_dec = dec.to_f
        max_radius = radius_arcmin.to_f
        return nil unless max_radius.positive?

        nearest = nil
        nearest_separation = Float::INFINITY

        catalog_rows.each do |row|
          separation = angular_separation_arcmin(target_ra, target_dec, row[:ra], row[:dec])
          next if separation > max_radius
          next unless separation < nearest_separation

          nearest = row
          nearest_separation = separation
        end

        nearest
      end

      def random_target
        target = galaxy_targets.sample
        return nil unless target

        {
          name: target[:name],
          ra: target[:ra],
          dec: target[:dec],
          u: target[:u],
          g: target[:g],
          r: target[:r],
          i: target[:i],
          z: target[:z]
        }
      end

      def galaxy_targets
        catalog_rows.reject { |row| row[:agn] }.map(&:dup)
      end

      def all_targets
        catalog_rows.map(&:dup)
      end

      private

      def catalog_rows
        @catalog_rows ||= CSV.read(CATALOG_PATH, headers: true).map do |row|
          {
            name: row["name"],
            ra: row["ra"].to_f,
            dec: row["dec"].to_f,
            u: row["u"].to_f,
            g: row["g"].to_f,
            r: row["r"].to_f,
            i: row["i"].to_f,
            z: row["z"].to_f,
            type: row["type"],
            notes: row["notes"],
            agn: parse_boolean(row["agn"]),
            sdss_dr: row["sdss_dr"].presence || "DR7"
          }
        end
      end

      def parse_boolean(value)
        value.to_s.strip.casecmp("true").zero?
      end

      def angular_separation_arcmin(ra1_deg, dec1_deg, ra2_deg, dec2_deg)
        ra1 = ra1_deg * DEG_TO_RAD
        dec1 = dec1_deg * DEG_TO_RAD
        ra2 = ra2_deg * DEG_TO_RAD
        dec2 = dec2_deg * DEG_TO_RAD

        delta_ra = ra2 - ra1
        delta_dec = dec2 - dec1

        a = Math.sin(delta_dec / 2.0)**2 +
            Math.cos(dec1) * Math.cos(dec2) * Math.sin(delta_ra / 2.0)**2
        c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt([1.0 - a, 0.0].max))

        c * RAD_TO_ARCMIN
      end
    end
  end
end
