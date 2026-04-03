class CreateGalexPhotometries < ActiveRecord::Migration[7.1]
  def up
    create_table :galex_photometries do |t|
      t.references :galaxy, null: false, foreign_key: true, index: true
      t.float :nuv_mag
      t.float :nuv_mag_err
      t.float :fuv_mag
      t.float :fuv_mag_err
      t.string :galex_objid
      t.string :galex_source, default: "GALEX_GR6_7"
      t.datetime :galex_checked_at
      t.timestamps
    end
  end

  def down
    drop_table :galex_photometries
  end
end
