class UseSdssObjidAsPrimaryKeyForObservations < ActiveRecord::Migration[7.1]
  def up
    add_column :observations, :sdss_objid, :string unless column_exists?(:observations, :sdss_objid)

    execute <<~SQL
      UPDATE observations
      SET sdss_objid = (
        SELECT galaxies.sdss_objid
        FROM galaxies
        WHERE galaxies.id = observations.galaxy_id
      )
      WHERE sdss_objid IS NULL OR sdss_objid = '';
    SQL

    rename_table :observations, :observations_old

    create_table :observations, id: :string, primary_key: :sdss_objid do |t|
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
      FROM observations_old
      WHERE sdss_objid IS NOT NULL AND sdss_objid <> '';
    SQL

    drop_table :observations_old
  end

  def down
    rename_table :observations, :observations_new

    create_table :observations do |t|
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
    add_foreign_key :observations, :galaxies

    execute <<~SQL
      INSERT INTO observations (
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
      FROM observations_new;
    SQL

    drop_table :observations_new
  end
end
