class CreateCalibrationRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :calibration_runs do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.text :result_json
      t.text :error_message
      t.integer :runtime_seconds

      t.timestamps
    end
  end
end
