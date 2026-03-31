class AddSdssStatusToGalaxies < ActiveRecord::Migration[7.1]
  def up
    add_column :galaxies, :sdss_status, :string
  end

  def down
    remove_column :galaxies, :sdss_status
  end
end
