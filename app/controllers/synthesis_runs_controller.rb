class SynthesisRunsController < ApplicationController
  def index
    @synthesis_runs = SynthesisRun.order(created_at: :desc)
  end

  def show
    @synthesis_run = SynthesisRun.find(params[:id])
    @spectrum_result = SpectrumResult.find_by(synthesis_run_id: @synthesis_run.id)
  end

  def new
    @synthesis_run = SynthesisRun.new
  end

  def create
    @synthesis_run = SynthesisRun.new(synthesis_run_params)
    @synthesis_run.status = "pending"
    unless ActiveModel::Type::Boolean.new.cast(params[:fetch_sdss])
      @synthesis_run.sdss_ra = 0.0
      @synthesis_run.sdss_dec = 0.0
    end

    if @synthesis_run.save
      SynthesisPipelineJob.perform_later(@synthesis_run.id)
      redirect_to @synthesis_run, notice: "Synthesis run created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def seed_test
    target = StellarPop::SdssLocalCatalog.random_target || { ra: 187.2779, dec: 2.0523 }
    sfh_model = %w[exponential constant burst].sample
    burst_age_gyr = sfh_model == "burst" ? [1.0, 2.0, 4.0, 8.0].sample : 2.0
    burst_width_gyr = sfh_model == "burst" ? [0.3, 0.5, 1.0].sample : 0.5

    synthesis_run = SynthesisRun.create!(
      name: "test_run_#{SecureRandom.hex(4)}",
      imf_type: %w[kroupa salpeter].sample,
      age_gyr: [1.0, 3.0, 5.0, 8.0, 10.0, 12.0].sample,
      metallicity_z: [0.008, 0.02, 0.03].sample,
      sfh_model: sfh_model,
      burst_age_gyr: burst_age_gyr,
      burst_width_gyr: burst_width_gyr,
      sdss_ra: target[:ra],
      sdss_dec: target[:dec],
      status: "pending"
    )

    SynthesisPipelineJob.perform_later(synthesis_run.id)
    redirect_to synthesis_run_path(synthesis_run), notice: "Test run enqueued."
  end

  private

  def synthesis_run_params
    params.require(:synthesis_run).permit(
      :name,
      :imf_type,
      :age_gyr,
      :metallicity_z,
      :sfh_model,
      :burst_age_gyr,
      :burst_width_gyr,
      :sdss_ra,
      :sdss_dec
    )
  end
end
