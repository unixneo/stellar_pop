module StellarPop
  class Blackboard
    attr_reader :spectral_buffer, :parameters, :results

    def initialize
      @spectral_buffer = {}
      @parameters      = {}
      @results         = {}
    end

    def write(key, value)
      @spectral_buffer[key] = value
    end

    def read(key)
      @spectral_buffer[key]
    end
  end
end
