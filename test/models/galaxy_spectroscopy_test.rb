require "test_helper"

class GalaxySpectroscopyTest < ActiveSupport::TestCase
  def build_galaxy(name: "NGC_TEST_SPEC")
    Galaxy.create!(
      name: name,
      ra: 150.1234,
      dec: 2.3456,
      galaxy_type: "elliptical",
      sdss_dr: "DR19"
    )
  end

  test "allows multiple spectroscopy rows for one galaxy" do
    galaxy = build_galaxy(name: "NGC_MULTI_SPEC")

    first = GalaxySpectroscopy.create!(
      galaxy: galaxy,
      redshift_z: 0.0123,
      current: false
    )
    second = GalaxySpectroscopy.create!(
      galaxy: galaxy,
      redshift_z: 0.0456,
      current: false
    )

    assert first.persisted?
    assert second.persisted?
    assert_equal 2, galaxy.galaxy_spectroscopies.count
  end

  test "setting one record current demotes other current records" do
    galaxy = build_galaxy(name: "NGC_CURRENT_SPEC")

    older = GalaxySpectroscopy.create!(
      galaxy: galaxy,
      redshift_z: 0.0101,
      redshift_source: "specobj_bestobjid",
      current: true
    )
    newer = GalaxySpectroscopy.create!(
      galaxy: galaxy,
      redshift_z: 0.0202,
      redshift_source: "nearest_spec",
      current: true
    )

    assert_equal false, older.reload.current
    assert_equal true, newer.reload.current
    assert_equal newer.id, galaxy.reload.galaxy_spectroscopy.id
  end
end
