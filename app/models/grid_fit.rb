class GridFit < ApplicationRecord
  STATUSES = %w[pending running complete failed].freeze

  validates :name, presence: true
  validates :sdss_ra, presence: true, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 360.0 }
  validates :sdss_dec, presence: true, numericality: { greater_than_or_equal_to: -90.0, less_than_or_equal_to: 90.0 }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
end
