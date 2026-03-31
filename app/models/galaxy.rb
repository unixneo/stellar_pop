class Galaxy < ApplicationRecord
  MAG_TYPES = %w[petrosian model unknown].freeze
  ID_MATCH_QUALITIES = %w[exact_objid coord_validated unverified].freeze
  REDSHIFT_CONFIDENCES = %w[high medium low].freeze

  has_many :synthesis_runs, dependent: :nullify
  has_many :grid_fits, dependent: :nullify
  has_many :observations, dependent: :destroy
  before_update :prevent_identity_coordinate_changes_for_dr19

  validates :name, presence: true
  validates :ra, presence: true
  validates :dec, presence: true
  validates :mag_type, inclusion: { in: MAG_TYPES }, allow_nil: true
  validates :id_match_quality, inclusion: { in: ID_MATCH_QUALITIES }, allow_nil: false
  validates :redshift_confidence, inclusion: { in: REDSHIFT_CONFIDENCES }, allow_nil: false

  def self.find_by_ra_dec(ra, dec, tolerance: 0.01)
    target_ra = ra.to_f
    target_dec = dec.to_f
    tol = tolerance.to_f
    return nil unless tol.positive?

    where(ra: (target_ra - tol)..(target_ra + tol), dec: (target_dec - tol)..(target_dec + tol))
      .to_a
      .min_by { |g| ((g.ra.to_f - target_ra)**2) + ((g.dec.to_f - target_dec)**2) }
  end

  def photometry_hash
    {
      u: mag_u,
      g: mag_g,
      r: mag_r,
      i: mag_i,
      z: mag_z,
      redshift_z: redshift_z
    }
  end

  private

  def prevent_identity_coordinate_changes_for_dr19
    return unless sdss_dr == "DR19"
    return unless will_save_change_to_name? || will_save_change_to_ra? || will_save_change_to_dec?

    errors.add(:base, "name, ra, dec are immutable for DR19 galaxies")
    throw :abort
  end
end
