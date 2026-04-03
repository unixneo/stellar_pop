class GalexPhotometry < ApplicationRecord
  belongs_to :galaxy

  validates :galaxy_id, presence: true
end
