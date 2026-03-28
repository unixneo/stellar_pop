require "faraday"
require "json"

module StellarPop
  class SdssClient
    API_URL = "https://skyserver.sdss.org/dr18/SkyServerWS/SearchTools/SqlSearch".freeze
    TIMEOUT_SECONDS = 30

    def initialize(connection: nil)
      @connection = connection || Faraday.new(
        url: API_URL,
        request: { timeout: TIMEOUT_SECONDS, open_timeout: TIMEOUT_SECONDS }
      )
    end

    def fetch_photometry(ra, dec, radius_arcmin: 0.5)
      sql = nearby_photometry_query(ra.to_f, dec.to_f, radius_arcmin.to_f)
      response = @connection.get(nil, cmd: sql, format: "json")
      payload = parse_json(response.body)
      row = extract_first_row(payload)
      return nil unless row

      {
        u: to_float_or_nil(row["u"] || row[:u]),
        g: to_float_or_nil(row["g"] || row[:g]),
        r: to_float_or_nil(row["r"] || row[:r]),
        i: to_float_or_nil(row["i"] || row[:i]),
        z: to_float_or_nil(row["z"] || row[:z])
      }
    rescue Faraday::Error, JSON::ParserError
      nil
    end

    private

    def nearby_photometry_query(ra, dec, radius_arcmin)
      <<~SQL
        SELECT TOP 1 objid, ra, dec, u, g, r, i, z
        FROM PhotoObj
        WHERE objid IN (
          SELECT objid
          FROM fGetNearbyObjEq(#{ra}, #{dec}, #{radius_arcmin})
        )
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
  end
end
