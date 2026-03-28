class AddRuntimeSecondsToGridFits < ActiveRecord::Migration[7.1]
  def change
    add_column :grid_fits, :runtime_seconds, :integer
  end
end
