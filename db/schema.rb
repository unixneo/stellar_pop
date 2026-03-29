# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_29_194100) do
  create_table "calibration_runs", force: :cascade do |t|
    t.string "name", null: false
    t.string "status", default: "pending", null: false
    t.text "result_json"
    t.text "error_message"
    t.integer "runtime_seconds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "progress_completed", default: 0, null: false
    t.integer "progress_total", default: 0, null: false
    t.string "current_step"
  end

  create_table "galaxies", force: :cascade do |t|
    t.string "name", null: false
    t.float "ra", null: false
    t.float "dec", null: false
    t.float "mag_u"
    t.float "mag_g"
    t.float "mag_r"
    t.float "mag_i"
    t.float "mag_z"
    t.float "err_u"
    t.float "err_g"
    t.float "err_r"
    t.float "err_i"
    t.float "err_z"
    t.float "extinction_u"
    t.float "extinction_g"
    t.float "extinction_r"
    t.float "extinction_i"
    t.float "extinction_z"
    t.string "galaxy_type"
    t.text "notes"
    t.boolean "agn", default: false, null: false
    t.string "sdss_dr"
    t.float "redshift_z"
    t.string "sdss_objid"
    t.string "source_catalog", default: "local", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "grid_fits", force: :cascade do |t|
    t.string "name"
    t.string "target_name"
    t.float "sdss_ra"
    t.float "sdss_dec"
    t.string "status", default: "pending"
    t.float "best_age_gyr"
    t.float "best_metallicity_z"
    t.string "best_sfh_model"
    t.string "best_imf_type"
    t.float "best_chi_squared"
    t.text "result_json"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "runtime_seconds"
    t.integer "galaxy_id"
    t.index ["galaxy_id"], name: "index_grid_fits_on_galaxy_id"
  end

  create_table "pipeline_configs", force: :cascade do |t|
    t.text "settings_json", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "spectrum_results", force: :cascade do |t|
    t.integer "synthesis_run_id", null: false
    t.text "wavelength_data"
    t.text "flux_data"
    t.text "sdss_photometry"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["synthesis_run_id"], name: "index_spectrum_results_on_synthesis_run_id"
  end

  create_table "synthesis_runs", force: :cascade do |t|
    t.string "name"
    t.string "status"
    t.string "imf_type"
    t.float "age_gyr"
    t.float "metallicity_z"
    t.string "sfh_model"
    t.float "sdss_ra"
    t.float "sdss_dec"
    t.float "chi_squared"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sdss_object_name"
    t.float "burst_age_gyr", default: 2.0
    t.float "burst_width_gyr", default: 0.5
    t.string "spectra_model", default: "basel"
    t.integer "wavelength_min", default: 350
    t.integer "wavelength_max", default: 900
    t.integer "galaxy_id"
    t.index ["galaxy_id"], name: "index_synthesis_runs_on_galaxy_id"
  end

  add_foreign_key "grid_fits", "galaxies"
  add_foreign_key "spectrum_results", "synthesis_runs"
  add_foreign_key "synthesis_runs", "galaxies"
end
