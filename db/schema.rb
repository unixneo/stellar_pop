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

ActiveRecord::Schema[7.1].define(version: 2026_03_28_173000) do
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
  end

  add_foreign_key "spectrum_results", "synthesis_runs"
end
