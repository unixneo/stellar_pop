require "test_helper"

class SynthesisPipelineJobTest < ActiveJob::TestCase
  class FakeIntegrator
    def initialize(blackboard, composite_spectrum:, error: nil)
      @blackboard = blackboard
      @composite_spectrum = composite_spectrum
      @error = error
    end

    def run
      raise @error if @error

      @blackboard.write(:composite_spectrum, @composite_spectrum)
    end
  end

  test "completes run and writes spectrum result when sdss coordinates are zero" do
    run = SynthesisRun.create!(
      name: "job-no-sdss",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "constant",
      sdss_ra: 0.0,
      sdss_dec: 0.0
    )

    composite = { 350.0 => 0.2, 360.0 => 0.8, 370.0 => 0.1 }
    fake_integrator_factory = lambda { |blackboard|
      FakeIntegrator.new(blackboard, composite_spectrum: composite)
    }

    with_stubbed_new(StellarPop::Integrator::SpectralIntegrator, fake_integrator_factory) do
      SynthesisPipelineJob.perform_now(run.id)
    end

    run.reload
    result = SpectrumResult.find_by!(synthesis_run_id: run.id)

    assert_equal "complete", run.status
    assert_nil run.error_message
    assert_nil run.chi_squared

    assert_equal [350.0, 360.0, 370.0], JSON.parse(result.wavelength_data)
    assert_equal [0.2, 0.8, 0.1], JSON.parse(result.flux_data)
    assert_nil result.sdss_photometry
  end

  test "stores sdss photometry and chi-squared when photometry is available" do
    run = SynthesisRun.create!(
      name: "job-with-sdss",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "exponential",
      sdss_ra: 187.2779,
      sdss_dec: 2.0523
    )

    # z-band lookup uses nearest to 913nm, which is 900nm in this test spectrum.
    composite = {
      354.0 => 1.0,
      477.0 => 1.0,
      623.0 => 2.0,
      763.0 => 1.0,
      900.0 => 1.0
    }
    fake_integrator_factory = lambda { |blackboard|
      FakeIntegrator.new(blackboard, composite_spectrum: composite)
    }

    fake_sdss_client = Object.new
    def fake_sdss_client.fetch_photometry(_ra, _dec, radius_arcmin: 0.5)
      _ = radius_arcmin
      { u: 0.0, g: 0.0, r: 0.0, i: 0.0, z: 0.0 }
    end

    with_stubbed_new(StellarPop::Integrator::SpectralIntegrator, fake_integrator_factory) do
      with_stubbed_new(StellarPop::SdssClient, fake_sdss_client) do
        SynthesisPipelineJob.perform_now(run.id)
      end
    end

    run.reload
    result = SpectrumResult.find_by!(synthesis_run_id: run.id)
    phot = JSON.parse(result.sdss_photometry)

    expected_chi_squared = StellarPop::SdssFilterConvolver.new.synthetic_magnitudes(composite).sum do |_band, synthetic_flux|
      ((synthetic_flux - 1.0)**2) / 1.0
    end

    assert_equal "complete", run.status
    assert_in_delta expected_chi_squared, run.chi_squared, 1e-9
    assert_equal({ "u" => 0.0, "g" => 0.0, "r" => 0.0, "i" => 0.0, "z" => 0.0 }, phot)
  end

  test "retries sdss fetch with backoff and succeeds on later attempt" do
    run = SynthesisRun.create!(
      name: "job-sdss-retry",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "constant",
      sdss_ra: 187.2779,
      sdss_dec: 2.0523
    )

    composite = {
      354.0 => 1.0,
      477.0 => 1.0,
      623.0 => 1.0,
      763.0 => 1.0,
      900.0 => 1.0
    }
    fake_integrator_factory = lambda { |blackboard|
      FakeIntegrator.new(blackboard, composite_spectrum: composite)
    }

    fake_sdss_client = Object.new
    fake_sdss_client.instance_variable_set(:@calls, 0)
    def fake_sdss_client.fetch_photometry(_ra, _dec, radius_arcmin: 0.5)
      _ = radius_arcmin
      @calls += 1
      return nil if @calls < 3

      { u: 0.0, g: 0.0, r: 0.0, i: 0.0, z: 0.0 }
    end
    def fake_sdss_client.calls
      @calls
    end

    with_stubbed_instance_method(SynthesisPipelineJob, :sleep_backoff, ->(_seconds) { nil }) do
      with_stubbed_new(StellarPop::Integrator::SpectralIntegrator, fake_integrator_factory) do
        with_stubbed_new(StellarPop::SdssClient, fake_sdss_client) do
          SynthesisPipelineJob.perform_now(run.id)
        end
      end
    end

    run.reload
    result = SpectrumResult.find_by!(synthesis_run_id: run.id)

    assert_equal 3, fake_sdss_client.calls
    assert_equal "complete", run.status
    assert_not_nil result.sdss_photometry
  end

  test "stores informational sdss note when coordinates are set but photometry is unavailable" do
    run = SynthesisRun.create!(
      name: "job-sdss-unavailable",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "constant",
      sdss_ra: 187.2779,
      sdss_dec: 2.0523
    )

    composite = { 350.0 => 0.5, 360.0 => 1.0, 370.0 => 0.3 }
    fake_integrator_factory = lambda { |blackboard|
      FakeIntegrator.new(blackboard, composite_spectrum: composite)
    }

    fake_sdss_client = Object.new
    def fake_sdss_client.fetch_photometry(_ra, _dec, radius_arcmin: 0.5)
      _ = radius_arcmin
      nil
    end

    with_stubbed_new(StellarPop::Integrator::SpectralIntegrator, fake_integrator_factory) do
      with_stubbed_new(StellarPop::SdssClient, fake_sdss_client) do
        SynthesisPipelineJob.perform_now(run.id)
      end
    end

    run.reload

    assert_equal "complete", run.status
    assert_equal "SDSS photometry unavailable - service timeout or no object found", run.error_message
    assert_nil run.chi_squared
  end

  test "marks run as failed and stores error message when pipeline raises" do
    run = SynthesisRun.create!(
      name: "job-failure",
      status: "pending",
      imf_type: "kroupa",
      age_gyr: 5.0,
      metallicity_z: 0.02,
      sfh_model: "constant",
      sdss_ra: 0.0,
      sdss_dec: 0.0
    )

    fake_integrator_factory = lambda { |blackboard|
      FakeIntegrator.new(blackboard, composite_spectrum: {}, error: RuntimeError.new("forced failure"))
    }

    with_stubbed_new(StellarPop::Integrator::SpectralIntegrator, fake_integrator_factory) do
      SynthesisPipelineJob.perform_now(run.id)
    end

    run.reload

    assert_equal "failed", run.status
    assert_match(/forced failure/, run.error_message)
    assert_equal 0, SpectrumResult.where(synthesis_run_id: run.id).count
  end

  private

  def with_stubbed_new(klass, replacement)
    singleton = class << klass; self; end

    original_new =
      if singleton.method_defined?(:new)
        singleton.instance_method(:new)
      else
        nil
      end

    singleton.define_method(:new) do |*args, **kwargs, &block|
      if replacement.respond_to?(:call)
        replacement.call(*args, **kwargs, &block)
      else
        replacement
      end
    end

    yield
  ensure
    singleton.send(:remove_method, :new)
    if original_new
      singleton.define_method(:new, original_new)
    else
      singleton.define_method(:new) { |*args, **kwargs, &block| super(*args, **kwargs, &block) }
    end
  end

  def with_stubbed_instance_method(klass, method_name, replacement_proc, &block)
    original_method = klass.instance_method(method_name)
    klass.define_method(method_name) do |*args, **kwargs, &method_block|
      replacement_proc.call(*args, **kwargs, &method_block)
    end

    block.call
  ensure
    klass.define_method(method_name, original_method)
  end
end
