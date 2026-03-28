class AddSdssObjectNameToSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :synthesis_runs, :sdss_object_name, :string
  end
end
