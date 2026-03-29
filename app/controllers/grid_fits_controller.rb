class GridFitsController < ApplicationController
  def index
    @grid_fits = GridFit.order(created_at: :desc)
  end

  def show
    @grid_fit = GridFit.find(params[:id])
    @ranked_results = parse_ranked_results(@grid_fit.result_json)
  end

  def new
    @grid_fit = GridFit.new
    @catalog_targets = Galaxy.where(agn: false).order(:name)
    @config = PipelineConfig.current
    @grid_ages = @config.float_array("grid_ages_gyr")
    @grid_metallicities = @config.float_array("grid_metallicities_z")
    @grid_sfh_models = @config.string_array("grid_sfh_models")
    @grid_imf_types = @config.string_array("grid_imf_types")
    @grid_burst_ages = @config.float_array("grid_burst_ages_gyr")
  end

  def create
    @grid_fit = GridFit.new(grid_fit_params)
    @grid_fit.target_name = params[:sdss_object_name].presence
    @grid_fit.status = "pending"
    selected_galaxy = find_selected_galaxy
    if selected_galaxy
      @grid_fit.galaxy_id = selected_galaxy.id
      @grid_fit.sdss_ra = selected_galaxy.ra
      @grid_fit.sdss_dec = selected_galaxy.dec
      @grid_fit.target_name = selected_galaxy.name
    elsif @grid_fit.sdss_ra.present? && @grid_fit.sdss_dec.present?
      @grid_fit.galaxy_id = Galaxy.find_by_ra_dec(@grid_fit.sdss_ra, @grid_fit.sdss_dec)&.id
    end

    if @grid_fit.save
      GridFitJob.perform_later(@grid_fit.id, sweep_params)
      redirect_to @grid_fit, notice: "Grid fit created."
    else
      @catalog_targets = Galaxy.where(agn: false).order(:name)
      @config = PipelineConfig.current
      @grid_ages = @config.float_array("grid_ages_gyr")
      @grid_metallicities = @config.float_array("grid_metallicities_z")
      @grid_sfh_models = @config.string_array("grid_sfh_models")
      @grid_imf_types = @config.string_array("grid_imf_types")
      @grid_burst_ages = @config.float_array("grid_burst_ages_gyr")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def grid_fit_params
    params.require(:grid_fit).permit(:name, :sdss_ra, :sdss_dec, :galaxy_id)
  end

  def parse_ranked_results(result_json)
    JSON.parse(result_json.presence || "[]")
  rescue JSON::ParserError
    []
  end

  def sweep_params
    config = PipelineConfig.current
    allowed_ages = config.float_array("grid_ages_gyr")
    allowed_metallicities = config.float_array("grid_metallicities_z")
    allowed_sfh_models = config.string_array("grid_sfh_models")
    allowed_imf_types = config.string_array("grid_imf_types")

    {
      ages_gyr: sanitize_float_array(params[:sweep_ages], allowed_ages),
      metallicities_z: sanitize_float_array(params[:sweep_metallicities], allowed_metallicities),
      sfh_models: sanitize_string_array(params[:sweep_sfh_models], allowed_sfh_models),
      imf_types: sanitize_string_array(params[:sweep_imf_types], allowed_imf_types)
    }
  end

  def sanitize_float_array(raw_values, allowed_values)
    selected = Array(raw_values).map { |v| v.to_f }.select { |v| allowed_values.include?(v) }.uniq
    selected.empty? ? allowed_values : selected
  end

  def sanitize_string_array(raw_values, allowed_values)
    selected = Array(raw_values).map(&:to_s).select { |v| allowed_values.include?(v) }.uniq
    selected.empty? ? allowed_values : selected
  end

  def find_selected_galaxy
    selected_name = params[:sdss_object_name].to_s.strip
    return nil if selected_name.empty?

    Galaxy.find_by(name: selected_name)
  end
end
