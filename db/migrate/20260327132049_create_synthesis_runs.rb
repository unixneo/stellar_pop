class CreateSynthesisRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :synthesis_runs do |t|
      t.string :name
      t.string :status
      t.string :imf_type
      t.float :age_gyr
      t.float :metallicity_z
      t.string :sfh_model
      t.float :sdss_ra
      t.float :sdss_dec
      t.float :chi_squared
      t.text :error_message

      t.timestamps
    end
  end
end
