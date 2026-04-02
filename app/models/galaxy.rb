class Galaxy < ApplicationRecord
  MAG_TYPES = %w[petrosian model unknown].freeze
  ID_MATCH_QUALITIES = %w[exact_objid coord_validated unverified].freeze
  REDSHIFT_CONFIDENCES = %w[high medium low].freeze

  has_many :synthesis_runs, dependent: :nullify
  has_many :grid_fits, dependent: :nullify
  has_many :observations, dependent: :destroy
  has_one :galaxy_photometry, dependent: :destroy
  has_many :galaxy_spectroscopies, dependent: :destroy
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
    phot = preferred_photometry
    spec = preferred_spectroscopy

    {
      u: phot&.mag_u,
      g: phot&.mag_g,
      r: phot&.mag_r,
      i: phot&.mag_i,
      z: phot&.mag_z,
      redshift_z: spec&.redshift_z
    }
  end

  def photometry_errors_hash
    phot = preferred_photometry
    {
      u: phot&.err_u,
      g: phot&.err_g,
      r: phot&.err_r,
      i: phot&.err_i,
      z: phot&.err_z
    }
  end

  def preferred_photometry
    galaxy_photometry || self
  end

  def preferred_spectroscopy
    galaxy_spectroscopy || self
  end

  # Compatibility accessor during has_one -> has_many transition.
  def galaxy_spectroscopy
    galaxy_spectroscopies.current.first || galaxy_spectroscopies.order(redshift_checked_at: :desc, id: :desc).first
  end

  private

  def prevent_identity_coordinate_changes_for_dr19
    return unless sdss_dr == "DR19"
    return unless will_save_change_to_name? || will_save_change_to_ra? || will_save_change_to_dec?

    errors.add(:base, "name, ra, dec are immutable for DR19 galaxies")
    throw :abort
  end
end
