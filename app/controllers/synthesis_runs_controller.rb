class SynthesisRunsController < ApplicationController
  def index
    @synthesis_runs = SynthesisRun.order(created_at: :desc)
  end

  def show
    @synthesis_run = SynthesisRun.find(params[:id])
  end

  def new
    @synthesis_run = SynthesisRun.new
  end

  def create
    @synthesis_run = SynthesisRun.new(synthesis_run_params)

    if @synthesis_run.save
      redirect_to @synthesis_run, notice: "Synthesis run created."
    else
      render :new, status: :unprocessable_entity
    end
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
