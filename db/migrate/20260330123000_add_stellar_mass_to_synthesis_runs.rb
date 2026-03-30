class AddStellarMassToSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :synthesis_runs, :stellar_mass, :float
  end
end
