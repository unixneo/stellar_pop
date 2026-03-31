class ObservationsController < ApplicationController
  SORT_COLUMNS = {
    "id" => "observations.id",
    "galaxy" => "galaxies.name",
    "sdss_objid" => "observations.sdss_objid",
    "source_paper" => "observations.source_paper",
    "age_gyr" => "observations.age_gyr",
    "metallicity_z" => "observations.metallicity_z",
    "stellar_mass" => "observations.stellar_mass",
    "sfr" => "observations.sfr",
    "method_used" => "observations.method_used",
    "created_at" => "observations.created_at",
    "updated_at" => "observations.updated_at"
  }.freeze

  def index
    @sort = params[:sort].to_s
    @sort = "created_at" unless SORT_COLUMNS.key?(@sort)
    @dir = params[:dir].to_s == "asc" ? "asc" : "desc"

    sort_sql = SORT_COLUMNS.fetch(@sort)
    @observations = Observation.includes(:galaxy).left_joins(:galaxy)
                               .order(Arel.sql("#{sort_sql} #{@dir}, observations.id #{@dir}"))
  end

  def show
    @observation = Observation.find(params[:id])
  end

  def new
    @observation = Observation.new
    @observation.galaxy_id = params[:galaxy_id] if params[:galaxy_id].present?
    load_galaxy_options
  end

  def edit
    @observation = Observation.find(params[:id])
    load_galaxy_options
  end

  def create
    @observation = Observation.new(observation_params)
    @observation.sdss_objid = @observation.galaxy&.sdss_objid
    if @observation.save
      redirect_to observation_path(@observation), notice: "Observation created."
    else
      load_galaxy_options
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @observation = Observation.find(params[:id])
    @observation.assign_attributes(observation_params)
    @observation.sdss_objid = @observation.galaxy&.sdss_objid
    if @observation.save
      redirect_to observation_path(@observation), notice: "Observation updated."
    else
      load_galaxy_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    observation = Observation.find(params[:id])
    observation.destroy!
    redirect_to observations_path, notice: "Observation deleted."
  end

  private

  def observation_params
    params.require(:observation).permit(
      :galaxy_id,
      :source_paper,
      :age_gyr,
      :metallicity_z,
      :stellar_mass,
      :sfr,
      :method_used,
      :notes
    )
  end

  def load_galaxy_options
    @galaxy_options = Galaxy.order(:name).pluck(:name, :id)
  end
end
