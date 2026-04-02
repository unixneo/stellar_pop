class GalaxyPhotometry < ApplicationRecord
  belongs_to :galaxy

  validates :galaxy_id, uniqueness: true
end
