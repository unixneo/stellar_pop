module StellarPop
  class SdssFilterConvolver
    FILTER_CURVES = {
      u: [
        [310.0, 0.050406], [320.0, 0.167973], [330.0, 0.411112], [340.0, 0.738991], [350.0, 0.975611],
        [360.0, 0.945959], [370.0, 0.673638], [380.0, 0.352322], [390.0, 0.135335], [400.0, 0.03818]
      ],
      g: [
        [400.0, 0.055298], [410.0, 0.111705], [420.0, 0.204656], [430.0, 0.340067], [440.0, 0.512499],
        [450.0, 0.700503], [460.0, 0.868391], [470.0, 0.976358], [480.0, 0.995615], [490.0, 0.920793],
        [500.0, 0.772363], [510.0, 0.587583], [520.0, 0.40542], [530.0, 0.253705], [540.0, 0.143993],
        [550.0, 0.074121], [560.0, 0.034605]
      ],
      r: [
        [560.0, 0.07956], [570.0, 0.166718], [580.0, 0.307522], [590.0, 0.499316], [600.0, 0.713643],
        [610.0, 0.897825], [620.0, 0.994277], [630.0, 0.969233], [640.0, 0.831677], [650.0, 0.628183],
        [660.0, 0.41766], [670.0, 0.244436], [680.0, 0.125925], [690.0, 0.057104], [700.0, 0.022794]
      ],
      i: [
        [700.0, 0.07956], [710.0, 0.166718], [720.0, 0.307522], [730.0, 0.499316], [740.0, 0.713643],
        [750.0, 0.897825], [760.0, 0.994277], [770.0, 0.969233], [780.0, 0.831677], [790.0, 0.628183],
        [800.0, 0.41766], [810.0, 0.244436], [820.0, 0.125925], [830.0, 0.057104], [840.0, 0.022794]
      ],
      z: [
        [820.0, 0.03555], [830.0, 0.070103], [840.0, 0.127972], [850.0, 0.216265], [860.0, 0.338335],
        [870.0, 0.490001], [880.0, 0.656956], [890.0, 0.815389], [900.0, 0.936879], [910.0, 0.996534],
        [920.0, 0.981273], [930.0, 0.894494], [940.0, 0.75484], [950.0, 0.589687], [960.0, 0.42646],
        [970.0, 0.285512], [980.0, 0.176954], [990.0, 0.101528], [1000.0, 0.053926], [1010.0, 0.026623],
        [1020.0, 0.012173], [1030.0, 0.005131], [1040.0, 0.001995], [1050.0, 0.000715]
      ]
    }.freeze

    def convolve(spectrum_hash, band)
      curve = FILTER_CURVES.fetch(band.to_sym) { raise ArgumentError, "unknown SDSS band: #{band}" }
      return 0.0 if spectrum_hash.nil? || spectrum_hash.empty?

      wavelengths = spectrum_hash.keys.map(&:to_f).sort
      return 0.0 if wavelengths.empty?

      weighted_flux_sum = 0.0
      transmission_sum = 0.0

      curve.each do |wavelength_nm, transmission|
        flux = interpolate_flux(spectrum_hash, wavelengths, wavelength_nm)
        weighted_flux_sum += flux * transmission
        transmission_sum += transmission
      end

      return 0.0 unless transmission_sum.positive?

      weighted_flux_sum / transmission_sum
    end

    def synthetic_magnitudes(spectrum_hash)
      FILTER_CURVES.keys.each_with_object({}) do |band, h|
        h[band] = convolve(spectrum_hash, band)
      end
    end

    private

    def interpolate_flux(spectrum_hash, sorted_wavelengths, wavelength_nm)
      return 0.0 if wavelength_nm < sorted_wavelengths.first || wavelength_nm > sorted_wavelengths.last

      exact = spectrum_hash[wavelength_nm]
      return exact.to_f if exact

      upper_index = sorted_wavelengths.bsearch_index { |wl| wl >= wavelength_nm }
      return 0.0 if upper_index.nil? || upper_index.zero?

      lower_wl = sorted_wavelengths[upper_index - 1]
      upper_wl = sorted_wavelengths[upper_index]

      lower_flux = spectrum_hash[lower_wl].to_f
      upper_flux = spectrum_hash[upper_wl].to_f
      return lower_flux if upper_wl == lower_wl

      fraction = (wavelength_nm - lower_wl) / (upper_wl - lower_wl)
      lower_flux + ((upper_flux - lower_flux) * fraction)
    end
  end
end
