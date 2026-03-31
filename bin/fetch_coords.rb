#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "uri"

GALAXY_NAMES = [
  "M87", "NGC1068", "NGC3184", "NGC3379", "NGC3690", "NGC4051", "NGC4151",
  "NGC4194", "NGC4261", "NGC4262", "NGC4321", "NGC4339", "NGC4350", "NGC4365",
  "NGC4387", "NGC4459", "NGC4472", "NGC4552", "NGC4564", "NGC4570", "NGC4579",
  "NGC4594", "NGC4621", "NGC4660", "NGC4874", "NGC4889"
].freeze

SIMBAD_TAP_URL = "https://simbad.cds.unistra.fr/simbad/sim-tap/sync"

def fetch_coords(name)
  adql = "SELECT b.ra, b.dec FROM basic b JOIN ident i ON i.oidref = b.oid WHERE i.id = '#{name}'"
  encoded_query = URI.encode_www_form_component(adql)
  query_string = "REQUEST=doQuery&LANG=ADQL&FORMAT=TSV&QUERY=#{encoded_query}"
  uri = URI("#{SIMBAD_TAP_URL}?#{query_string}")
  request = Net::HTTP::Get.new(uri)

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    raise "HTTP #{response.code} #{response.message}"
  end

  lines = response.body.to_s.lines.map(&:strip).reject(&:empty?)
  return nil if lines.size < 2

  values = lines[1].split("\t")
  return nil if values.size < 2

  { ra: values[0], dec: values[1] }
end

GALAXY_NAMES.each_with_index do |name, index|
  begin
    result = fetch_coords(name)

    if result
      puts "#{name}\t#{result[:ra]}\t#{result[:dec]}"
    else
      warn "#{name}\tERROR\tNo row returned"
    end
  rescue StandardError => e
    warn "#{name}\tERROR\t#{e.class}: #{e.message}"
  ensure
    sleep(0.5) if index < GALAXY_NAMES.length - 1
  end
end
