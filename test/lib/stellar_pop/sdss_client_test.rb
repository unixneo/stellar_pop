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

    assert_equal(
      {
        u: 18.12, g: 17.45, r: 16.8, i: 16.41, z: 16.12,
        petro_u: 18.12, petro_g: 17.45, petro_r: 16.8, petro_i: 16.41, petro_z: 16.12,
        model_u: nil, model_g: nil, model_r: nil, model_i: nil, model_z: nil
      },
      phot
    )
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
end
