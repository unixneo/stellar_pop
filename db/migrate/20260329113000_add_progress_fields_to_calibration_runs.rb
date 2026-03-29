class AddProgressFieldsToCalibrationRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :calibration_runs, :progress_completed, :integer, default: 0, null: false
    add_column :calibration_runs, :progress_total, :integer, default: 0, null: false
    add_column :calibration_runs, :current_step, :string
  end
end
