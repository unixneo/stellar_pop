class CalibrationRun < ApplicationRecord
  STATUSES = %w[pending running complete failed].freeze

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :runtime_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :progress_completed, numericality: { greater_than_or_equal_to: 0 }
  validates :progress_total, numericality: { greater_than_or_equal_to: 0 }
end
