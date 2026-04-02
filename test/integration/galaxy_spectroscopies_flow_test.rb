require "test_helper"

class GalaxySpectroscopiesFlowTest < ActionDispatch::IntegrationTest
  def setup
    @galaxy = Galaxy.create!(
      name: "NGC_FLOW_SPEC",
      ra: 170.1111,
      dec: 3.2222,
      galaxy_type: "spiral",
      sdss_dr: "DR19"
    )
    @spec1 = GalaxySpectroscopy.create!(
      galaxy: @galaxy,
      redshift_z: 0.0111,
      redshift_source: "specobj_bestobjid",
      redshift_confidence: "high",
      current: true
    )
    @spec2 = GalaxySpectroscopy.create!(
      galaxy: @galaxy,
      redshift_z: 0.0222,
      redshift_source: "manual",
      redshift_confidence: "medium",
      current: false
    )
  end

  test "show renders multiple spectroscopy cards" do
    get galaxy_path(@galaxy)
    assert_response :success

    assert_match "Spectroscopy", @response.body
    assert_match @spec1.redshift_z.to_s, @response.body
    assert_match @spec2.redshift_z.to_s, @response.body
    assert_match "Add Spectroscopy", @response.body
  end

  test "create update destroy spectroscopy record" do
    get new_galaxy_spectroscopy_path(@galaxy)
    assert_response :success

    assert_difference("GalaxySpectroscopy.count", 1) do
      post galaxy_spectroscopies_path(@galaxy), params: {
        galaxy_spectroscopy: {
          redshift_z: 0.0333,
          z_err: 0.0001,
          z_warning: 0,
          redshift_source: "specobj_bestobjid",
          redshift_confidence: "high",
          current: false,
          sdss_dr: "DR19"
        }
      }
    end
    assert_redirected_to galaxy_path(@galaxy)

    created = GalaxySpectroscopy.order(:id).last
    patch galaxy_spectroscopy_path(@galaxy, created), params: {
      galaxy_spectroscopy: {
        redshift_z: 0.0444,
        current: true,
        redshift_confidence: "high"
      }
    }
    assert_redirected_to galaxy_path(@galaxy)
    assert_equal 0.0444, created.reload.redshift_z
    assert_equal true, created.current
    assert_equal false, @spec1.reload.current

    assert_difference("GalaxySpectroscopy.count", -1) do
      delete galaxy_spectroscopy_path(@galaxy, created)
    end
    assert_redirected_to galaxy_path(@galaxy)
  end
end
