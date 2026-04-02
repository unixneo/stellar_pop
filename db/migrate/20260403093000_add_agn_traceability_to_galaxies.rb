class AddAgnTraceabilityToGalaxies < ActiveRecord::Migration[7.1]
  def change
    add_column :galaxies, :agn_source, :string
    add_column :galaxies, :agn_method, :string
    add_column :galaxies, :agn_confidence, :string
    add_column :galaxies, :agn_checked_at, :datetime
  end
end
