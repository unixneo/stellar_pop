class CreateObservations < ActiveRecord::Migration[7.1]
  def change
    create_table :observations do |t|
      t.references :galaxy, null: false, foreign_key: true
      t.string :source_paper
      t.float :age_gyr
      t.float :metallicity_z
      t.float :stellar_mass
      t.float :sfr
      t.string :method_used
      t.text :notes

      t.timestamps
    end
  end
end
