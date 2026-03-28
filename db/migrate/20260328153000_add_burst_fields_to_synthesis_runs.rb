class AddBurstFieldsToSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :synthesis_runs, :burst_age_gyr, :float, default: 2.0
    add_column :synthesis_runs, :burst_width_gyr, :float, default: 0.5
  end
end
