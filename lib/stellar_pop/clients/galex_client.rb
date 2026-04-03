require "net/http"
require "uri"
require "nokogiri"

module StellarPop
  module Clients
    class GalexClient
      ENDPOINT = "https://galex.stsci.edu/gR6/?mode=VOTable&RA=%<ra>s&DEC=%<dec>s&SR=%<sr>s".freeze
      DEFAULT_RADIUS_ARCSEC = 5.0
      ARCSEC_PER_DEGREE = 3600.0

      class << self
        def fetch(ra:, dec:, radius_arcsec: DEFAULT_RADIUS_ARCSEC)
          query_ra = ra.to_f
          query_dec = dec.to_f
          radius_arcsec_f = radius_arcsec.to_f
          radius_deg = radius_arcsec_f / ARCSEC_PER_DEGREE

          url = format(ENDPOINT, ra: query_ra, dec: query_dec, sr: radius_deg)
          uri = URI(url)

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: 15,
            read_timeout: 30
          ) do |http|
            http.request(Net::HTTP::Get.new(uri))
          end

          return nil unless response.is_a?(Net::HTTPSuccess)

          doc = Nokogiri::XML(response.body.to_s)
          doc.remove_namespaces!

          fields = doc.xpath("//VOTABLE/RESOURCE/TABLE/FIELD")
          return nil if fields.empty?

          field_names = fields.map { |f| f["name"].to_s.strip }
          index = build_field_index(field_names)

          rows = doc.xpath("//VOTABLE/RESOURCE/TABLE/DATA/TABLEDATA/TR")
          return nil if rows.empty?

          best = nil
          best_distance_arcsec = nil

          rows.each do |tr|
            values = tr.xpath("./TD").map { |td| td.text.to_s.strip }

            source_ra = value_as_float(values, index[:ra])
            source_dec = value_as_float(values, index[:dec])
            next if source_ra.nil? || source_dec.nil?

            distance_arcsec = angular_separation_arcsec(query_ra, query_dec, source_ra, source_dec)
            next if distance_arcsec.nil? || distance_arcsec > radius_arcsec_f

            candidate = {
              nuv_mag: value_as_float(values, index[:nuv_mag]),
              nuv_mag_err: value_as_float(values, index[:nuv_mag_err]),
              fuv_mag: value_as_float(values, index[:fuv_mag]),
              fuv_mag_err: value_as_float(values, index[:fuv_mag_err]),
              galex_objid: value_as_string(values, index[:objid]),
              galex_source: "GALEX_GR6_7",
              match_distance_arcsec: distance_arcsec
            }

            if best.nil? || distance_arcsec < best_distance_arcsec
              best = candidate
              best_distance_arcsec = distance_arcsec
            end
          end

          best
        rescue StandardError => e
          Rails.logger.warn("GalexClient.fetch failed: #{e.class}: #{e.message}")
          nil
        end

        private

        def build_field_index(field_names)
          normalized = {}
          field_names.each_with_index do |name, idx|
            normalized[name.to_s.strip.upcase] = idx
          end

          {
            nuv_mag: normalized["NUV_MAG"],
            nuv_mag_err: normalized["NUV_MAGERR"],
            fuv_mag: normalized["FUV_MAG"],
            fuv_mag_err: normalized["FUV_MAGERR"],
            objid: normalized["OBJID"],
            ra: normalized["RA"],
            dec: normalized["DEC"]
          }
        end

        def value_as_float(values, idx)
          return nil if idx.nil?

          raw = values[idx]
          return nil if raw.nil? || raw.empty?

          Float(raw)
        rescue ArgumentError, TypeError
          nil
        end

        def value_as_string(values, idx)
          return nil if idx.nil?

          raw = values[idx].to_s.strip
          raw.empty? ? nil : raw
        end

        def angular_separation_arcsec(ra1_deg, dec1_deg, ra2_deg, dec2_deg)
          ra1 = radians(ra1_deg)
          dec1 = radians(dec1_deg)
          ra2 = radians(ra2_deg)
          dec2 = radians(dec2_deg)

          delta_ra = ra2 - ra1
          delta_dec = dec2 - dec1

          sin_ddec = Math.sin(delta_dec / 2.0)
          sin_dra = Math.sin(delta_ra / 2.0)
          a = (sin_ddec * sin_ddec) + (Math.cos(dec1) * Math.cos(dec2) * sin_dra * sin_dra)
          a = [[a, 0.0].max, 1.0].min
          c = 2.0 * Math.asin(Math.sqrt(a))

          c * (180.0 / Math::PI) * ARCSEC_PER_DEGREE
        rescue StandardError
          nil
        end

        def radians(value_deg)
          value_deg.to_f * Math::PI / 180.0
        end
      end
    end
  end
end
