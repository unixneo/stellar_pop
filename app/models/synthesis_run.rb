class SynthesisRun < ApplicationRecord
  IMF_TYPES = %w[kroupa salpeter].freeze
  SFH_MODELS = %w[exponential constant burst].freeze
  STATUSES = %w[pending running complete failed].freeze

  validates :name, presence: true
  validates :imf_type, presence: true, inclusion: { in: IMF_TYPES }
  validates :sfh_model, presence: true, inclusion: { in: SFH_MODELS }
  validates :age_gyr, presence: true, numericality: { greater_than: 0.0, less_than_or_equal_to: 13.8 }
  validates :metallicity_z, presence: true, numericality: { greater_than: 0.0, less_than_or_equal_to: 0.05 }
  validates :sdss_ra, presence: true, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 360.0 }
  validates :sdss_dec, presence: true, numericality: { greater_than_or_equal_to: -90.0, less_than_or_equal_to: 90.0 }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
end
