require "faraday"
require "json"

module StellarPop
  class SdssClient
    VALID_RELEASES = %w[DR18 DR19].freeze
    DEFAULT_RELEASE = "DR19".freeze
    API_URL_TEMPLATE = "https://skyserver.sdss.org/%<release>s/SkyServerWS/SearchTools/SqlSearch".freeze
    API_URL = "https://skyserver.sdss.org/dr19/SkyServerWS/SearchTools/SqlSearch".freeze
    TIMEOUT_SECONDS = 30
    attr_reader :last_failure_reason, :release, :api_url

    def initialize(connection: nil, release: DEFAULT_RELEASE)
      @release = normalize_release(release)
      @api_url = self.class.api_url_for(@release)
      @connection = connection || Faraday.new(
        url: @api_url,
        request: { timeout: TIMEOUT_SECONDS, open_timeout: TIMEOUT_SECONDS }
      )
    end

    def self.api_url_for(release)
      normalized = release.to_s.upcase
      normalized = DEFAULT_RELEASE unless VALID_RELEASES.include?(normalized)
      format(API_URL_TEMPLATE, release: normalized.downcase)
    end

    def release_label
      @release
    end

    def fetch_photometry(ra, dec, radius_arcmin: 0.5)
      @last_failure_reason = nil
      sql = nearby_photometry_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      build_photometry_hash(row)
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    def fetch_photometry_by_objid(objid)
      @last_failure_reason = nil
      sql = photometry_by_objid_query(objid)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      build_photometry_hash(row)
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    def fetch_photometry_profiles(ra, dec, radius_arcmin: 0.5)
      @last_failure_reason = nil
      sql = nearby_photometry_profiles_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      petrosian = {
        u: to_float_or_nil(row["petroMag_u"] || row[:petroMag_u]),
        g: to_float_or_nil(row["petroMag_g"] || row[:petroMag_g]),
        r: to_float_or_nil(row["petroMag_r"] || row[:petroMag_r]),
        i: to_float_or_nil(row["petroMag_i"] || row[:petroMag_i]),
        z: to_float_or_nil(row["petroMag_z"] || row[:petroMag_z])
      }
      model = {
        u: to_float_or_nil(row["modelMag_u"] || row[:modelMag_u]),
        g: to_float_or_nil(row["modelMag_g"] || row[:modelMag_g]),
        r: to_float_or_nil(row["modelMag_r"] || row[:modelMag_r]),
        i: to_float_or_nil(row["modelMag_i"] || row[:modelMag_i]),
        z: to_float_or_nil(row["modelMag_z"] || row[:modelMag_z])
      }

      {
        objid: (row["objid"] || row[:objid]).to_s.presence,
        petrosian: petrosian,
        model: model
      }
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    def fetch_redshift(ra, dec, radius_arcmin: 0.5)
      @last_failure_reason = nil
      sql = nearby_redshift_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      if row.nil?
        fallback_sql = nearby_spec_redshift_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
        fallback_response = @connection.get(nil, cmd: fallback_sql, format: "json")
        fallback_payload = parse_json(fallback_response.body)
        row = extract_first_row(fallback_payload)
      end
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      {
        redshift_z: to_float_or_nil(row["z"] || row[:z]),
        redshift_err: to_float_or_nil(row["zErr"] || row[:zErr] || row["zerr"] || row[:zerr]),
        redshift_warning: to_int_or_nil(row["zWarning"] || row[:zWarning] || row["zwarning"] || row[:zwarning]),
        objid: (row["objid"] || row[:objid]).to_s.presence
      }
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    def fetch_redshift_by_objid(objid)
      @last_failure_reason = nil
      sql = redshift_by_objid_query(objid)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      {
        redshift_z: to_float_or_nil(row["z"] || row[:z]),
        redshift_err: to_float_or_nil(row["zErr"] || row[:zErr] || row["zerr"] || row[:zerr]),
        redshift_warning: to_int_or_nil(row["zWarning"] || row[:zWarning] || row["zwarning"] || row[:zwarning]),
        objid: objid.to_s.presence
      }
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    def fetch_nearest_spec_match(ra, dec, radius_arcmin: 2.0)
      @last_failure_reason = nil
      sql = nearest_spec_match_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      unless row
        @last_failure_reason = :no_object_found
        return nil
      end

      {
        objid: (row["objid"] || row[:objid]).to_s.presence,
        spec_objid: (row["specObjID"] || row[:specObjID] || row["specobjid"] || row[:specobjid]).to_s.presence,
        redshift_z: to_float_or_nil(row["z"] || row[:z]),
        redshift_err: to_float_or_nil(row["zErr"] || row[:zErr] || row["zerr"] || row[:zerr]),
        redshift_warning: to_int_or_nil(row["zWarning"] || row[:zWarning] || row["zwarning"] || row[:zwarning]),
        distance_arcmin: to_float_or_nil(row["distance"] || row[:distance])
      }
    rescue Faraday::TimeoutError
      @last_failure_reason = :timeout
      nil
    rescue Faraday::ConnectionFailed
      @last_failure_reason = :api_unreachable
      nil
    rescue JSON::ParserError
      @last_failure_reason = :invalid_response
      nil
    rescue Faraday::Error
      @last_failure_reason = :request_error
      nil
    end

    private

    def build_photometry_hash(row)
      petro_u = to_float_or_nil(row["petroMag_u"] || row[:petroMag_u] || row["u"] || row[:u])
      petro_g = to_float_or_nil(row["petroMag_g"] || row[:petroMag_g] || row["g"] || row[:g])
      petro_r = to_float_or_nil(row["petroMag_r"] || row[:petroMag_r] || row["r"] || row[:r])
      petro_i = to_float_or_nil(row["petroMag_i"] || row[:petroMag_i] || row["i"] || row[:i])
      petro_z = to_float_or_nil(row["petroMag_z"] || row[:petroMag_z] || row["z"] || row[:z])

      {
        u: petro_u,
        g: petro_g,
        r: petro_r,
        i: petro_i,
        z: petro_z,
        petro_u: petro_u,
        petro_g: petro_g,
        petro_r: petro_r,
        petro_i: petro_i,
        petro_z: petro_z,
        petro_err_u: to_float_or_nil(row["petroMagErr_u"] || row[:petroMagErr_u]),
        petro_err_g: to_float_or_nil(row["petroMagErr_g"] || row[:petroMagErr_g]),
        petro_err_r: to_float_or_nil(row["petroMagErr_r"] || row[:petroMagErr_r]),
        petro_err_i: to_float_or_nil(row["petroMagErr_i"] || row[:petroMagErr_i]),
        petro_err_z: to_float_or_nil(row["petroMagErr_z"] || row[:petroMagErr_z]),
        model_u: to_float_or_nil(row["modelMag_u"] || row[:modelMag_u]),
        model_g: to_float_or_nil(row["modelMag_g"] || row[:modelMag_g]),
        model_r: to_float_or_nil(row["modelMag_r"] || row[:modelMag_r]),
        model_i: to_float_or_nil(row["modelMag_i"] || row[:modelMag_i]),
        model_z: to_float_or_nil(row["modelMag_z"] || row[:modelMag_z]),
        model_err_u: to_float_or_nil(row["modelMagErr_u"] || row[:modelMagErr_u]),
        model_err_g: to_float_or_nil(row["modelMagErr_g"] || row[:modelMagErr_g]),
        model_err_r: to_float_or_nil(row["modelMagErr_r"] || row[:modelMagErr_r]),
        model_err_i: to_float_or_nil(row["modelMagErr_i"] || row[:modelMagErr_i]),
        model_err_z: to_float_or_nil(row["modelMagErr_z"] || row[:modelMagErr_z]),
        extinction_u: to_float_or_nil(row["extinction_u"] || row[:extinction_u]),
        extinction_g: to_float_or_nil(row["extinction_g"] || row[:extinction_g]),
        extinction_r: to_float_or_nil(row["extinction_r"] || row[:extinction_r]),
        extinction_i: to_float_or_nil(row["extinction_i"] || row[:extinction_i]),
        extinction_z: to_float_or_nil(row["extinction_z"] || row[:extinction_z]),
        redshift_z: to_float_or_nil(row["spec_z"] || row[:spec_z]),
        z_err: to_float_or_nil(row["spec_zErr"] || row[:spec_zErr] || row["spec_zerr"] || row[:spec_zerr]),
        z_warning: to_int_or_nil(row["spec_zWarning"] || row[:spec_zWarning] || row["spec_zwarning"] || row[:spec_zwarning]),
        sdss_clean: to_bool_or_nil(row["clean"] || row[:clean])
      }
    end

    def nearby_photometry_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 p.objid, p.ra, p.dec,
        p.petroMag_u, p.petroMag_g, p.petroMag_r, p.petroMag_i, p.petroMag_z,
        p.petroMagErr_u, p.petroMagErr_g, p.petroMagErr_r, p.petroMagErr_i, p.petroMagErr_z,
        p.modelMag_u, p.modelMag_g, p.modelMag_r, p.modelMag_i, p.modelMag_z,
        p.modelMagErr_u, p.modelMagErr_g, p.modelMagErr_r, p.modelMagErr_i, p.modelMagErr_z,
        p.extinction_u, p.extinction_g, p.extinction_r, p.extinction_i, p.extinction_z,
        p.clean,
        s.z AS spec_z, s.zErr AS spec_zErr, s.zWarning AS spec_zWarning
        FROM PhotoObj AS p
        JOIN fGetNearbyObjEq(#{ra}, #{dec}, #{radius_arcmin}) AS n
          ON n.objid = p.objid
        LEFT JOIN SpecObj AS s
          ON s.bestObjID = p.objid
        WHERE p.type = 3
        ORDER BY n.distance ASC
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def photometry_by_objid_query(objid)
      <<~SQL
        SELECT p.objid, p.ra, p.dec,
        p.petroMag_u, p.petroMag_g, p.petroMag_r, p.petroMag_i, p.petroMag_z,
        p.petroMagErr_u, p.petroMagErr_g, p.petroMagErr_r, p.petroMagErr_i, p.petroMagErr_z,
        p.modelMag_u, p.modelMag_g, p.modelMag_r, p.modelMag_i, p.modelMag_z,
        p.modelMagErr_u, p.modelMagErr_g, p.modelMagErr_r, p.modelMagErr_i, p.modelMagErr_z,
        p.extinction_u, p.extinction_g, p.extinction_r, p.extinction_i, p.extinction_z,
        p.clean,
        s.z AS spec_z, s.zErr AS spec_zErr, s.zWarning AS spec_zWarning
        FROM PhotoObj AS p
        LEFT JOIN SpecObj AS s
          ON s.bestObjID = p.objid
        WHERE p.objid = #{objid}
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def nearby_photometry_profiles_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 p.objid, p.ra, p.dec,
        p.petroMag_u, p.petroMag_g, p.petroMag_r, p.petroMag_i, p.petroMag_z,
        p.petroMagErr_u, p.petroMagErr_g, p.petroMagErr_r, p.petroMagErr_i, p.petroMagErr_z,
        p.modelMag_u, p.modelMag_g, p.modelMag_r, p.modelMag_i, p.modelMag_z,
        p.modelMagErr_u, p.modelMagErr_g, p.modelMagErr_r, p.modelMagErr_i, p.modelMagErr_z,
        p.extinction_u, p.extinction_g, p.extinction_r, p.extinction_i, p.extinction_z,
        p.clean,
        s.z AS spec_z, s.zErr AS spec_zErr, s.zWarning AS spec_zWarning
        FROM PhotoObj AS p
        JOIN fGetNearbyObjEq(#{ra}, #{dec}, #{radius_arcmin}) AS n
          ON n.objid = p.objid
        LEFT JOIN SpecObj AS s
          ON s.bestObjID = p.objid
        WHERE p.type = 3
        ORDER BY n.distance ASC
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def nearby_redshift_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 p.objid, s.z, s.zErr
        FROM PhotoObj AS p
        JOIN fGetNearbyObjEq(#{ra}, #{dec}, #{radius_arcmin}) AS n
          ON n.objid = p.objid
        JOIN SpecObj AS s
          ON s.bestObjID = p.objid
        ORDER BY n.distance ASC
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def redshift_by_objid_query(objid)
      <<~SQL
        SELECT TOP 1 z, zErr, zWarning
        FROM SpecObj
        WHERE bestObjID = #{objid}
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def nearby_spec_redshift_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 s.bestObjID AS objid, s.z, s.zErr, s.zWarning
        FROM SpecObj AS s
        JOIN fGetNearbySpecObjEq(#{ra}, #{dec}, #{radius_arcmin}) AS n
          ON n.specObjID = s.specObjID
        ORDER BY n.distance ASC
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def nearest_spec_match_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 s.bestObjID AS objid, s.specObjID, s.z, s.zErr, s.zWarning, n.distance
        FROM fGetNearbySpecObjEq(#{ra}, #{dec}, #{radius_arcmin}) AS n
        JOIN SpecObj AS s
          ON s.specObjID = n.specObjID
        ORDER BY n.distance ASC
      SQL
        .gsub(/\s+/, " ")
        .strip
    end

    def parse_json(body)
      return body if body.is_a?(Array) || body.is_a?(Hash)

      JSON.parse(body.to_s)
    end

    def extract_first_row(payload)
      case payload
      when Array
        table = payload.find do |entry|
          next false unless entry.is_a?(Hash)

          table_name = entry["TableName"] || entry[:TableName] || entry["tableName"] || entry[:tableName]
          table_name.to_s == "Table1"
        end
        return nil unless table.is_a?(Hash)

        rows = table["Rows"] || table[:Rows] || table["rows"] || table[:rows]
        return nil unless rows.is_a?(Array) && rows.any?

        rows.first
      when Hash
        rows = payload["Rows"] || payload[:Rows] || payload["rows"] || payload[:rows]
        return rows.first if rows.is_a?(Array) && rows.any?

        results = payload["data"] || payload[:data] || payload["result"] || payload[:result]
        return results.first if results.is_a?(Array) && results.any?

        nil
      else
        nil
      end
    end

    def to_float_or_nil(value)
      return nil if value.nil?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def to_int_or_nil(value)
      return nil if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def to_bool_or_nil(value)
      return nil if value.nil?

      case value
      when true, "true", "TRUE", 1, "1"
        true
      when false, "false", "FALSE", 0, "0"
        false
      else
        nil
      end
    end

    def normalize_release(raw_release)
      value = raw_release.to_s.upcase
      VALID_RELEASES.include?(value) ? value : DEFAULT_RELEASE
    end
  end
end
