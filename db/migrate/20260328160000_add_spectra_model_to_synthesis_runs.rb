class AddSpectraModelToSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :synthesis_runs, :spectra_model, :string, default: "basel"
  end
end
