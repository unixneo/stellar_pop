require "yaml"

module StellarPop
  module Calibration
    class BenchmarkCatalog
      FILE_PATH = Rails.root.join("lib/data/calibration/benchmarks.yml").freeze

      class << self
        def all
          payload = YAML.safe_load(File.read(FILE_PATH), permitted_classes: [], aliases: false) || {}
          Array(payload["benchmarks"]).map { |row| symbolize(row) }
        end

        private

        def symbolize(value)
          case value
          when Hash
            value.each_with_object({}) { |(k, v), out| out[k.to_sym] = symbolize(v) }
          when Array
            value.map { |v| symbolize(v) }
          else
            value
          end
        end
      end
    end
  end
end
