module StellarPop
  class StellarMassEstimator
    SPEED_OF_LIGHT_KM_S = 299_792.458
    HUBBLE_CONSTANT_KM_S_MPC = 70.0
    DECELERATION_PARAMETER = -0.55
    SOLAR_ABS_MAG_R = 4.65

    IMF_MULTIPLIERS = {
      "kroupa" => 1.0,
      "salpeter" => 1.25,
      "chabrier" => 0.9
    }.freeze

    SFH_BASE_MASS_TO_LIGHT = {
      "constant" => 4.0,
      "exponential" => 3.0,
      "delayed_exponential" => 3.5,
      "burst" => 2.0
    }.freeze

    class << self
      def estimate(sfh_model:, imf_type:, age_gyr:, observed_r_mag:, redshift_z:, burst_age_gyr: nil, mass_log_offset_dex: 0.0)
        new(
          sfh_model: sfh_model,
          imf_type: imf_type,
          age_gyr: age_gyr,
          observed_r_mag: observed_r_mag,
          redshift_z: redshift_z,
          burst_age_gyr: burst_age_gyr,
          mass_log_offset_dex: mass_log_offset_dex
        ).estimate
      end
    end

    def initialize(sfh_model:, imf_type:, age_gyr:, observed_r_mag:, redshift_z:, burst_age_gyr: nil, mass_log_offset_dex: 0.0)
      @sfh_model = sfh_model.to_s
      @imf_type = imf_type.to_s
      @age_gyr = age_gyr.to_f
      @observed_r_mag = observed_r_mag.to_f
      @redshift_z = redshift_z.to_f
      @burst_age_gyr = burst_age_gyr.to_f
      @mass_log_offset_dex = mass_log_offset_dex.to_f
    end

    def estimate
      return nil unless @redshift_z.positive?

      abs_mag_r = @observed_r_mag - distance_modulus
      luminosity_r_lsun = 10.0**(-0.4 * (abs_mag_r - SOLAR_ABS_MAG_R))
      return nil unless luminosity_r_lsun.positive?

      mass_to_light = mass_to_light_ratio
      return nil unless mass_to_light.positive?

      base_mass = luminosity_r_lsun * mass_to_light
      base_mass * (10.0**@mass_log_offset_dex)
    rescue StandardError
      nil
    end

    private

    def distance_modulus
      luminosity_distance_mpc = approximate_luminosity_distance_mpc
      5.0 * Math.log10(luminosity_distance_mpc) + 25.0
    end

    def approximate_luminosity_distance_mpc
      linear_mpc = (SPEED_OF_LIGHT_KM_S / HUBBLE_CONSTANT_KM_S_MPC) * @redshift_z
      correction = 1.0 + (0.5 * (1.0 - DECELERATION_PARAMETER) * @redshift_z)
      [linear_mpc * correction, 1.0e-6].max
    end

    def mass_to_light_ratio
      sfh_base = SFH_BASE_MASS_TO_LIGHT.fetch(@sfh_model, SFH_BASE_MASS_TO_LIGHT["constant"])
      imf_multiplier = IMF_MULTIPLIERS.fetch(@imf_type, IMF_MULTIPLIERS["kroupa"])
      age_scale = [(@age_gyr / 10.0)**0.7, 0.05].max

      burst_scale =
        if @sfh_model == "burst" && @burst_age_gyr.positive?
          [[@burst_age_gyr / 2.0, 0.5].max, 2.0].min**0.3
        else
          1.0
        end

      sfh_base * imf_multiplier * age_scale * burst_scale
    end
  end
end
