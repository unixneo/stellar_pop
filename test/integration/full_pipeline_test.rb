require "test_helper"

class FullPipelineTest < ActiveSupport::TestCase
  test "pipeline job runs end-to-end and persists a normalized spectrum" do
    run = SynthesisRun.create!(
      name: "integration-full-pipeline",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "exponential",
      sdss_ra: 0.0,
      sdss_dec: 0.0
    )

    deterministic_masses = [0.6, 0.8, 1.0, 1.2, 2.0, 5.0, 10.0]

    with_stubbed_instance_method(StellarPop::KnowledgeSources::ImfSampler, :sample, ->(_n) { deterministic_masses }) do
      SynthesisPipelineJob.perform_now(run.id)
    end

    run.reload
    result = SpectrumResult.find_by!(synthesis_run_id: run.id)

    wavelengths = JSON.parse(result.wavelength_data)
    fluxes = JSON.parse(result.flux_data)

    assert_equal "complete", run.status
    assert_nil run.error_message
    assert wavelengths.any?
    assert_equal wavelengths.length, fluxes.length
    assert_in_delta 1.0, fluxes.max.to_f, 1e-9
  end

  private

  def with_stubbed_instance_method(klass, method_name, replacement_proc)
    original_method = klass.instance_method(method_name)
    klass.define_method(method_name) do |*args, **kwargs, &method_block|
      replacement_proc.call(*args, **kwargs, &method_block)
    end

    yield
  ensure
    klass.define_method(method_name, original_method)
  end
end
