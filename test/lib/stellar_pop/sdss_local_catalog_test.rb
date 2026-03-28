require "test_helper"

class SdssLocalCatalogTest < ActiveSupport::TestCase
  test "lookup finds nearby catalog object within radius" do
    phot = StellarPop::SdssLocalCatalog.lookup(187.2779, 2.0523, radius_arcmin: 1.0)

    assert_not_nil phot
    assert_in_delta 13.99292, phot[:u], 1e-6
    assert_in_delta 12.9987, phot[:g], 1e-6
  end

  test "lookup returns nil when no object is in radius" do
    assert_nil StellarPop::SdssLocalCatalog.lookup(0.0, 0.0, radius_arcmin: 1.0)
  end

  test "lookup_target returns matched object metadata including name" do
    target = StellarPop::SdssLocalCatalog.lookup_target(187.2779, 2.0523, radius_arcmin: 1.0)

    assert_not_nil target
    assert_equal "3C273", target[:name]
    assert_in_delta 13.99292, target[:u], 1e-6
  end

  test "random_target returns expected keys" do
    target = StellarPop::SdssLocalCatalog.random_target

    assert_not_nil target
    assert_equal %i[name ra dec u g r i z], target.keys
    assert target[:name].is_a?(String)
  end
end
