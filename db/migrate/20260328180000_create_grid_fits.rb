class CreateGridFits < ActiveRecord::Migration[7.1]
  def change
    create_table :grid_fits do |t|
      t.string :name
      t.string :target_name
      t.float :sdss_ra
      t.float :sdss_dec
      t.string :status, default: "pending"
      t.float :best_age_gyr
      t.float :best_metallicity_z
      t.string :best_sfh_model
      t.string :best_imf_type
      t.float :best_chi_squared
      t.text :result_json
      t.text :error_message

      t.timestamps
    end
  end
end
