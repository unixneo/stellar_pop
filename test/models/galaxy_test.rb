require "test_helper"

class GalaxyTest < ActiveSupport::TestCase
  def build_galaxy
    Galaxy.create!(
      name: "Test Galaxy",
      ra: 150.1234,
      dec: 2.3456,
      sdss_objid: "1234567890123456789",
      sdss_dr: "DR19",
      source_catalog: "test"
    )
  end

  test "allows create with identity fields" do
    galaxy = build_galaxy
    assert galaxy.persisted?
  end

  test "locks sdss_objid on update" do
    galaxy = build_galaxy
    assert_not galaxy.update(sdss_objid: "9876543210987654321")
    assert_includes galaxy.errors[:sdss_objid], "is immutable after create"
  end

  test "locks ra and dec on update" do
    galaxy = build_galaxy

    assert_not galaxy.update(ra: 151.0)
    assert_includes galaxy.errors[:ra], "is immutable after create"

    assert_not galaxy.update(dec: 3.0)
    assert_includes galaxy.errors[:dec], "is immutable after create"
  end

  test "allows updating mutable metadata fields" do
    galaxy = build_galaxy
    assert galaxy.update(name: "Renamed Galaxy", notes: "updated")
    assert_equal "Renamed Galaxy", galaxy.reload.name
  end
end
