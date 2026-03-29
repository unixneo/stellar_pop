require "test_helper"

class SynthesisRunTest < ActiveSupport::TestCase
  def build_valid_run(attrs = {})
    SynthesisRun.new(
      {
        name: "validation-run",
        status: "pending",
        imf_type: "kroupa",
        age_gyr: 5.0,
        metallicity_z: 0.02,
        sfh_model: "exponential",
        sdss_ra: 187.2779,
        sdss_dec: 2.0523
      }.merge(attrs)
    )
  end

  test "is valid with expected attributes" do
    assert build_valid_run.valid?
  end

  test "requires core fields" do
    run = build_valid_run(name: nil, imf_type: nil, sfh_model: nil, age_gyr: nil, metallicity_z: nil, sdss_ra: nil, sdss_dec: nil)

    assert_not run.valid?
    assert_includes run.errors[:name], "can't be blank"
    assert_includes run.errors[:imf_type], "can't be blank"
    assert_includes run.errors[:sfh_model], "can't be blank"
    assert_includes run.errors[:age_gyr], "can't be blank"
    assert_includes run.errors[:metallicity_z], "can't be blank"
    assert_includes run.errors[:sdss_ra], "can't be blank"
    assert_includes run.errors[:sdss_dec], "can't be blank"
  end

  test "enforces allowed categorical values" do
    run = build_valid_run(imf_type: "invalid", sfh_model: "invalid", status: "invalid")

    assert_not run.valid?
    assert_includes run.errors[:imf_type], "is not included in the list"
    assert_includes run.errors[:sfh_model], "is not included in the list"
    assert_includes run.errors[:status], "is not included in the list"
  end

  test "accepts chabrier as a valid imf_type" do
    run = build_valid_run(imf_type: "chabrier")

    assert run.valid?
  end

  test "enforces numeric ranges" do
    run = build_valid_run(
      age_gyr: 14.0,
      metallicity_z: 0.0,
      sdss_ra: 361.0,
      sdss_dec: -91.0
    )

    assert_not run.valid?
    assert_includes run.errors[:age_gyr], "must be less than or equal to 13.8"
    assert_includes run.errors[:metallicity_z], "must be greater than 0.0"
    assert_includes run.errors[:sdss_ra], "must be less than or equal to 360.0"
    assert_includes run.errors[:sdss_dec], "must be greater than or equal to -90.0"
  end
end
