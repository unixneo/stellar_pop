class GalaxySpectroscopy < ApplicationRecord
  belongs_to :galaxy

  scope :current, -> { where(current: true) }

  before_save :demote_other_current_rows, if: :current?

  private

  def demote_other_current_rows
    galaxy.galaxy_spectroscopies.where.not(id: id).where(current: true).update_all(current: false)
  end
end
