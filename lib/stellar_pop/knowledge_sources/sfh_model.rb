module StellarPop
  module KnowledgeSources
    class SfhModel
      def exponential_decay(age_gyr, tau)
        validate_non_negative!(age_gyr, "age_gyr")
        validate_positive!(tau, "tau")

        Math.exp(-age_gyr.to_f / tau.to_f)
      end

      def constant(age_gyr)
        validate_non_negative!(age_gyr, "age_gyr")
        1.0
      end

      def delayed_exponential(age_gyr, tau = 3.0)
        validate_non_negative!(age_gyr, "age_gyr")
        validate_positive!(tau, "tau")

        t = age_gyr.to_f
        tau_f = tau.to_f
        (t / (tau_f**2)) * Math.exp(-t / tau_f)
      end

      def burst(age_gyr, burst_age_gyr, width_gyr)
        validate_non_negative!(age_gyr, "age_gyr")
        validate_non_negative!(burst_age_gyr, "burst_age_gyr")
        validate_positive!(width_gyr, "width_gyr")

        delta = age_gyr.to_f - burst_age_gyr.to_f
        sigma = width_gyr.to_f
        Math.exp(-(delta**2) / (2.0 * sigma**2))
      end

      def weights(model, age_bins, options = {})
        ages = normalize_age_bins(age_bins)

        raw = ages.map do |age|
          case model
          when :exponential
            exponential_decay(age, fetch_option(options, :tau))
          when :delayed_exponential
            delayed_exponential(age, options.fetch(:tau, options.fetch("tau", 3.0)))
          when :constant
            constant(age)
          when :burst
            burst(
              age,
              fetch_option(options, :burst_age_gyr),
              fetch_option(options, :width_gyr)
            )
          else
            raise ArgumentError, "unknown model: #{model.inspect}"
          end
        end

        normalize(raw)
      end

      private

      def normalize_age_bins(age_bins)
        unless age_bins.is_a?(Array) && !age_bins.empty?
          raise ArgumentError, "age_bins must be a non-empty Array"
        end

        age_bins.map do |age|
          validate_non_negative!(age, "age bin")
          age.to_f
        end
      end

      def fetch_option(options, key)
        return options[key] if options.key?(key)
        return options[key.to_s] if options.key?(key.to_s)

        raise ArgumentError, "missing option: #{key}"
      end

      def normalize(values)
        sum = values.sum.to_f
        raise ArgumentError, "weights sum to zero; cannot normalize" unless sum.positive?

        values.map { |v| v.to_f / sum }
      end

      def validate_positive!(value, name)
        raise ArgumentError, "#{name} must be > 0" unless value.to_f.positive?
      end

      def validate_non_negative!(value, name)
        raise ArgumentError, "#{name} must be >= 0" unless value.to_f >= 0.0
      end
    end
  end
end
