require "test_helper"

class PipelineConfigTest < ActiveSupport::TestCase
  test "default multi benchmark target flag is false" do
    PipelineConfig.delete_all
    config = PipelineConfig.current

    assert_equal false, ActiveModel::Type::Boolean.new.cast(config.fetch("calibration_allow_multi_benchmark_targets"))
  end

  test "update_from_form persists multi benchmark target flag" do
    config = PipelineConfig.current
    config.update_from_form(calibration_allow_multi_benchmark_targets: "1")

    assert_equal true, ActiveModel::Type::Boolean.new.cast(config.reload.fetch("calibration_allow_multi_benchmark_targets"))
  end

  test "default mass log offset is zero" do
    PipelineConfig.delete_all
    config = PipelineConfig.current

    assert_in_delta 0.0, config.float_value("calibration_mass_log_offset_dex"), 1.0e-12
  end

  test "update_from_form persists mass log offset" do
    config = PipelineConfig.current
    config.update_from_form(calibration_mass_log_offset_dex: "0.0845")

    assert_in_delta 0.0845, config.reload.float_value("calibration_mass_log_offset_dex"), 1.0e-9
  end
end
