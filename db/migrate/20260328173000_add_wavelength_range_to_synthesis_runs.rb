class AddWavelengthRangeToSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :synthesis_runs, :wavelength_min, :integer, default: 350
    add_column :synthesis_runs, :wavelength_max, :integer, default: 900
  end
end
