class Galaxy < ApplicationRecord
  has_many :synthesis_runs, dependent: :nullify
  has_many :grid_fits, dependent: :nullify
  has_many :observations, dependent: :destroy

  validates :name, presence: true
  validates :ra, presence: true
  validates :dec, presence: true

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
end
