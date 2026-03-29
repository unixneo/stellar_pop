module StellarPop
  class KCorrection
    VALID_MAX_REDSHIFT = 0.1

    class << self
      def correct(magnitudes, redshift_z)
        return magnitudes unless magnitudes.is_a?(Hash)

        z = redshift_z.to_f
        return magnitudes if z <= 0.0
        return corrected_magnitudes(magnitudes, z) if z < VALID_MAX_REDSHIFT

        log_high_redshift_warning(z)
        magnitudes
      end

      private

      def corrected_magnitudes(magnitudes, z)
        u = magnitudes[:u].to_f
        g = magnitudes[:g].to_f
        r = magnitudes[:r].to_f
        i = magnitudes[:i].to_f
        z_mag = magnitudes[:z].to_f

        u_minus_r = u - r
        g_minus_r = g - r

        k_u = (-4.457 * z) + (5.485 * u_minus_r * z)
        k_g = (-2.087 * z) + (1.190 * g_minus_r * z)
        k_r = (-1.127 * z) + (1.200 * g_minus_r * z)
        k_i = (-0.775 * z) + (0.958 * g_minus_r * z)
        k_z = (-0.514 * z) + (0.765 * g_minus_r * z)

        {
          u: u - k_u,
          g: g - k_g,
          r: r - k_r,
          i: i - k_i,
          z: z_mag - k_z
        }
      end

      def log_high_redshift_warning(redshift)
        message = format(
          "KCorrection skipped: z=%.5f is outside valid range for first-order approximation (z < 0.1).",
          redshift
        )

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.warn(message)
        else
          warn(message)
        end
      end
    end
  end
end
