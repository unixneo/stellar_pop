class GridFitsController < ApplicationController
  AGES_GYR = [1.0, 3.0, 5.0, 8.0, 10.0, 12.0].freeze
  METALLICITIES_Z = [0.0006, 0.0020, 0.0063, 0.0200, 0.0632].freeze
  SFH_MODELS = %w[exponential constant burst].freeze
  IMF_TYPES = %w[kroupa salpeter].freeze

  def index
    @grid_fits = GridFit.order(created_at: :desc)
  end

  def show
    @grid_fit = GridFit.find(params[:id])
    @ranked_results = parse_ranked_results(@grid_fit.result_json)
  end

  def new
    @grid_fit = GridFit.new
    @catalog_targets = StellarPop::SdssLocalCatalog.all_targets.sort_by { |target| target[:name].to_s }
  end

  def create
    @grid_fit = GridFit.new(grid_fit_params)
    @grid_fit.target_name = params[:sdss_object_name].presence
    @grid_fit.status = "pending"

    if @grid_fit.save
      GridFitJob.perform_later(@grid_fit.id, sweep_params)
      redirect_to @grid_fit, notice: "Grid fit created."
    else
      @catalog_targets = StellarPop::SdssLocalCatalog.all_targets.sort_by { |target| target[:name].to_s }
      render :new, status: :unprocessable_entity
    end
  end

  private

  def grid_fit_params
    params.require(:grid_fit).permit(:name, :sdss_ra, :sdss_dec)
  end

  def parse_ranked_results(result_json)
    JSON.parse(result_json.presence || "[]")
  rescue JSON::ParserError
    []
  end

  def sweep_params
    {
      ages_gyr: sanitize_float_array(params[:sweep_ages], AGES_GYR),
      metallicities_z: sanitize_float_array(params[:sweep_metallicities], METALLICITIES_Z),
      sfh_models: sanitize_string_array(params[:sweep_sfh_models], SFH_MODELS),
      imf_types: sanitize_string_array(params[:sweep_imf_types], IMF_TYPES)
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
end
