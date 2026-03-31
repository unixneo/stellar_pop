class Observation < ApplicationRecord
  belongs_to :galaxy

  validates :galaxy_id, presence: true
  validates :sdss_objid, presence: true

  before_validation :assign_sdss_objid_from_galaxy

  private

  def assign_sdss_objid_from_galaxy
    return if sdss_objid.present?

    self.sdss_objid = galaxy&.sdss_objid
  end
end
