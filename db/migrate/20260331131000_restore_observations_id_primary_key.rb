class RestoreObservationsIdPrimaryKey < ActiveRecord::Migration[7.1]
  def up
    rename_table :observations, :observations_old

    create_table :observations do |t|
      t.string :sdss_objid, null: false
      t.integer :galaxy_id, null: false
      t.string :source_paper
      t.float :age_gyr
      t.float :metallicity_z
      t.float :stellar_mass
      t.float :sfr
      t.string :method_used
      t.text :notes
      t.timestamps
    end

    add_index :observations, :galaxy_id
    add_index :observations, :sdss_objid
    add_foreign_key :observations, :galaxies

    execute <<~SQL
      INSERT INTO observations (
        sdss_objid,
        galaxy_id,
        source_paper,
        age_gyr,
        metallicity_z,
        stellar_mass,
        sfr,
        method_used,
        notes,
        created_at,
        updated_at
      )
      SELECT
        sdss_objid,
        galaxy_id,
        source_paper,
        age_gyr,
        metallicity_z,
        stellar_mass,
        sfr,
        method_used,
        notes,
        created_at,
        updated_at
      FROM observations_old;
    SQL

    drop_table :observations_old
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore sdss_objid primary key after allowing multiple rows per object."
  end
end
