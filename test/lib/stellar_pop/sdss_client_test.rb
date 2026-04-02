require "test_helper"

class SdssClientTest < ActiveSupport::TestCase
  class FakeConnection
    attr_reader :last_params

    def initialize(body: nil, error: nil)
      @body = body
      @error = error
    end

    def get(_path = nil, params = {})
      @last_params = params
      raise @error if @error

      Struct.new(:body).new(@body)
    end
  end

  test "parses sdss Table1 Rows payload and returns ugriz floats" do
    body = [
      {
        "TableName" => "Table1",
        "Rows" => [
          {
            "objid" => 123,
            "ra" => 187.2779,
            "dec" => 2.0523,
            "u" => "18.12",
            "g" => "17.45",
            "r" => "16.80",
            "i" => "16.41",
            "z" => "16.12"
          }
        ]
      }
    ].to_json
    connection = FakeConnection.new(body: body)
    client = StellarPop::SdssClient.new(connection: connection)

    phot = client.fetch_photometry(187.2779, 2.0523)

    assert_equal 18.12, phot[:u]
    assert_equal 17.45, phot[:g]
    assert_equal 16.8, phot[:r]
    assert_equal 16.41, phot[:i]
    assert_equal 16.12, phot[:z]
    assert_equal 18.12, phot[:petro_u]
    assert_equal 17.45, phot[:petro_g]
    assert_equal 16.8, phot[:petro_r]
    assert_equal 16.41, phot[:petro_i]
    assert_equal 16.12, phot[:petro_z]
    assert_nil phot[:model_u]
    assert_nil phot[:model_g]
    assert_nil phot[:model_r]
    assert_nil phot[:model_i]
    assert_nil phot[:model_z]
    assert_nil phot[:redshift_z]
    assert_includes connection.last_params[:cmd], "fGetNearbyObjEq(187.2779, 2.0523, 0.5)"
    assert_equal "json", connection.last_params[:format]
  end

  test "returns nil when Table1 is missing" do
    body = [{ "TableName" => "OtherTable", "Rows" => [{ "u" => "1" }] }].to_json
    client = StellarPop::SdssClient.new(connection: FakeConnection.new(body: body))

    assert_nil client.fetch_photometry(10.0, 20.0)
  end

  test "returns nil when Table1 rows are empty" do
    body = [{ "TableName" => "Table1", "Rows" => [] }].to_json
    client = StellarPop::SdssClient.new(connection: FakeConnection.new(body: body))

    assert_nil client.fetch_photometry(10.0, 20.0)
  end

  test "returns nil on JSON parse errors" do
    client = StellarPop::SdssClient.new(connection: FakeConnection.new(body: "not-json"))

    assert_nil client.fetch_photometry(10.0, 20.0)
  end

  test "returns nil on Faraday errors" do
    error = Faraday::ConnectionFailed.new("network down")
    client = StellarPop::SdssClient.new(connection: FakeConnection.new(error: error))

    assert_nil client.fetch_photometry(10.0, 20.0)
  end

  test "parses spectral class/subclass payload for agn classification inputs" do
    body = [
      {
        "TableName" => "Table1",
        "Rows" => [
          {
            "specObjID" => "123456789",
            "class" => "GALAXY",
            "subClass" => "AGN BROADLINE",
            "z" => "0.0042",
            "zErr" => "0.0001",
            "zWarning" => "0"
          }
        ]
      }
    ].to_json
    connection = FakeConnection.new(body: body)
    client = StellarPop::SdssClient.new(connection: connection)

    row = client.fetch_spectral_classification_by_objid("987654321")

    assert_equal "123456789", row[:spec_objid]
    assert_equal "GALAXY", row[:object_class]
    assert_equal "AGN BROADLINE", row[:object_subclass]
    assert_in_delta 0.0042, row[:redshift_z], 1e-8
    assert_in_delta 0.0001, row[:redshift_err], 1e-8
    assert_equal 0, row[:redshift_warning]
    assert_includes connection.last_params[:cmd], "WHERE bestObjID = 987654321"
  end
end
