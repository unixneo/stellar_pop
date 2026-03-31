#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

INPUT_PATH = "/var/stellar_pop/GALAXY.md"
SDSS_SQL_URL = "https://skyserver.sdss.org/dr19/SkyServerWS/SearchTools/SqlSearch"
SLEEP_SECONDS = 1.0

def build_sql(ra, dec)
  ra_min = ra - 0.15
  ra_max = ra + 0.15
  dec_min = dec - 0.15
  dec_max = dec + 0.15

  <<~SQL
    SELECT top 1 objid, ra, dec
    FROM Galaxy
    WHERE ra BETWEEN #{ra_min} AND #{ra_max}
    AND dec BETWEEN #{dec_min} AND #{dec_max}
    ORDER BY (power(ra-#{ra},2) + power(dec-#{dec},2))
  SQL
end

def fetch_sdss_row(sql)
  uri = URI(SDSS_SQL_URL)
  uri.query = URI.encode_www_form("cmd" => sql, "format" => "json")

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end

  raise "HTTP #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

  body = response.body.to_s.strip
  return nil if body.empty?

  result = JSON.parse(body)
  return nil unless result.is_a?(Array) && result[0].is_a?(Hash)

  rows = result[0]["Rows"]
  return nil unless rows.is_a?(Array) && !rows.empty?

  rows.first
end

unless File.exist?(INPUT_PATH)
  warn "Input file not found: #{INPUT_PATH}"
  exit 1
end

lines = File.readlines(INPUT_PATH, chomp: true).reject { |line| line.strip.empty? }

lines.each_with_index do |line, idx|
  begin
    parts = line.split("\t")
    if parts.size < 3
      warn "#{line}\tERROR\tMalformed input line"
      next
    end

    name = parts[0].to_s.strip
    ra = Float(parts[1])
    dec = Float(parts[2])
    sql = build_sql(ra, dec)
    row = fetch_sdss_row(sql)

    if row
      objid = row["objid"]
      puts "#{name}\t#{objid}"
    else
      puts "#{name}\tNO_MATCH"
    end
  rescue StandardError => e
    warn "#{name}\tERROR\t#{e.class}: #{e.message}"
    puts "#{name}\tNO_MATCH"
  ensure
    sleep(SLEEP_SECONDS) if idx < lines.length - 1
  end
end
