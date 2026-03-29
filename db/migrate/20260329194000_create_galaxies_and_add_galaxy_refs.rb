class CreateGalaxiesAndAddGalaxyRefs < ActiveRecord::Migration[7.1]
  def change
    create_table :galaxies do |t|
      t.string :name, null: false
      t.float :ra, null: false
      t.float :dec, null: false

      t.float :mag_u
      t.float :mag_g
      t.float :mag_r
      t.float :mag_i
      t.float :mag_z

      t.float :err_u
      t.float :err_g
      t.float :err_r
      t.float :err_i
      t.float :err_z

      t.float :extinction_u
      t.float :extinction_g
      t.float :extinction_r
      t.float :extinction_i
      t.float :extinction_z

      t.string :galaxy_type
      t.text :notes
      t.boolean :agn, default: false, null: false
      t.string :sdss_dr
      t.float :redshift_z
      t.string :sdss_objid
      t.string :source_catalog, default: "local", null: false

      t.timestamps
    end

    add_reference :synthesis_runs, :galaxy, foreign_key: true, null: true
    add_reference :grid_fits, :galaxy, foreign_key: true, null: true
  end
end
