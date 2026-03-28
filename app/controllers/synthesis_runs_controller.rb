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
    synthesis_run = SynthesisRun.create!(
      name: "test_run_1",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "exponential",
      sdss_ra: 187.2779,
      sdss_dec: 2.0523,
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
      :sdss_ra,
      :sdss_dec
    )
  end
end
