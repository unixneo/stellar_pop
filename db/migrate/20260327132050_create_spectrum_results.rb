class CreateSpectrumResults < ActiveRecord::Migration[7.1]
  def change
    create_table :spectrum_results do |t|
      t.references :synthesis_run, null: false, foreign_key: true
      t.text :wavelength_data
      t.text :flux_data
      t.text :sdss_photometry

      t.timestamps
    end
  end
end
