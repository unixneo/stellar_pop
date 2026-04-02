require "csv"

class GalaxiesController < ApplicationController
  SORT_COLUMNS = {
    "name" => "name",
    "galaxy_type" => "galaxy_type",
    "ra" => "ra",
    "dec" => "dec",
    "sdss_dr" => "sdss_dr",
    "source_catalog" => "source_catalog"
  }.freeze

  def index
    @active_sdss_release = PipelineConfig.current.sdss_dataset_release
    @query = params[:q].to_s.strip
    @sort = SORT_COLUMNS[params[:sort].to_s] || "name"
    @dir = params[:dir].to_s == "desc" ? "desc" : "asc"
    scope = Galaxy.includes(:galaxy_photometry, :galaxy_spectroscopies)
                 .where(sdss_dr: @active_sdss_release)
                 .order(Arel.sql("#{@sort} #{@dir}"))
    if @query.present?
      like = "%#{@query.downcase}%"
      scope = scope.where("lower(name) LIKE :q OR lower(galaxy_type) LIKE :q", q: like)
    end
    @galaxies = scope
  end

  def show
    @galaxy = Galaxy.find(params[:id])
    @photometry = @galaxy.galaxy_photometry
    @spectroscopies = @galaxy.galaxy_spectroscopies.order(current: :desc, redshift_checked_at: :desc, id: :desc)
  end

  def new
    @galaxy = Galaxy.new
  end

  def edit
    @galaxy = Galaxy.find(params[:id])
  end

  def create
    @galaxy = Galaxy.new(galaxy_params)
    if @galaxy.save
      redirect_to galaxy_path(@galaxy), notice: "Galaxy created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @galaxy = Galaxy.find(params[:id])
    if @galaxy.update(galaxy_params)
      redirect_to galaxy_path(@galaxy), notice: "Galaxy updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    galaxy = Galaxy.find(params[:id])
    galaxy.destroy!
    redirect_to galaxies_path, notice: "Galaxy deleted."
  end

  def import
    upload = params[:csv_file]
    if upload.blank?
      redirect_to galaxies_path, alert: "Choose a CSV file to import."
      return
    end

    created = 0
    updated = 0
    skipped = 0
    errors = []

    CSV.foreach(upload.path, headers: true) do |row|
      attrs, photometry_attrs, spectroscopy_attrs = row_to_attrs(row.to_h)
      if attrs[:name].blank? || attrs[:ra].nil? || attrs[:dec].nil?
        skipped += 1
        next
      end

      galaxy =
        Galaxy.find_by(name: attrs[:name]) ||
        Galaxy.find_by_ra_dec(attrs[:ra], attrs[:dec], tolerance: 0.001) ||
        Galaxy.new

      was_new = galaxy.new_record?
      galaxy.assign_attributes(attrs)
      if galaxy.save
        if photometry_attrs.any?
          phot = GalaxyPhotometry.find_or_initialize_by(galaxy_id: galaxy.id)
          phot.update!(photometry_attrs)
        end
        if spectroscopy_attrs.any?
          spec = GalaxySpectroscopy.find_or_initialize_by(galaxy_id: galaxy.id, current: true)
          spec.update!(spectroscopy_attrs)
        end
        was_new ? created += 1 : updated += 1
      else
        skipped += 1
        errors << "#{attrs[:name]}: #{galaxy.errors.full_messages.join(', ')}"
      end
    end

    summary = "Import complete: created=#{created}, updated=#{updated}, skipped=#{skipped}"
    summary += ". Errors: #{errors.first(3).join(' | ')}" if errors.any?
    redirect_to galaxies_path, notice: summary
  rescue CSV::MalformedCSVError => e
    redirect_to galaxies_path, alert: "CSV parse error: #{e.message}"
  end

  private

  def galaxy_params
    params.require(:galaxy).permit(
      :name, :ra, :dec,
      :galaxy_type, :notes, :agn,
      :sdss_dr, :sdss_objid, :source_catalog
    )
  end

  def row_to_attrs(row)
    attrs = {}
    attrs[:name] = value_for(row, "name")
    attrs[:ra] = to_float(value_for(row, "ra"))
    attrs[:dec] = to_float(value_for(row, "dec"))
    attrs[:galaxy_type] = value_for(row, "galaxy_type", "type")
    attrs[:notes] = value_for(row, "notes")
    attrs[:agn] = to_bool(value_for(row, "agn"))
    attrs[:sdss_dr] = value_for(row, "sdss_dr")
    attrs[:sdss_objid] = value_for(row, "sdss_objid", "objid")
    attrs[:source_catalog] = value_for(row, "source_catalog")
    photometry_attrs = {
      mag_u: to_float(value_for(row, "mag_u", "u")),
      mag_g: to_float(value_for(row, "mag_g", "g")),
      mag_r: to_float(value_for(row, "mag_r", "r")),
      mag_i: to_float(value_for(row, "mag_i", "i")),
      mag_z: to_float(value_for(row, "mag_z", "z")),
      err_u: to_float(value_for(row, "err_u")),
      err_g: to_float(value_for(row, "err_g")),
      err_r: to_float(value_for(row, "err_r")),
      err_i: to_float(value_for(row, "err_i")),
      err_z: to_float(value_for(row, "err_z")),
      extinction_u: to_float(value_for(row, "extinction_u")),
      extinction_g: to_float(value_for(row, "extinction_g")),
      extinction_r: to_float(value_for(row, "extinction_r")),
      extinction_i: to_float(value_for(row, "extinction_i")),
      extinction_z: to_float(value_for(row, "extinction_z"))
    }.compact
    spectroscopy_attrs = {
      redshift_z: to_float(value_for(row, "redshift_z")),
      sdss_dr: value_for(row, "sdss_dr")
    }.compact

    [attrs.compact, photometry_attrs, spectroscopy_attrs]
  end

  def value_for(row, *keys)
    keys.each do |key|
      return row[key] if row.key?(key)
      return row[key.to_s] if row.key?(key.to_s)
    end
    nil
  end

  def to_float(value)
    return nil if value.nil?
    text = value.to_s.strip
    return nil if text.empty?
    Float(text)
  rescue ArgumentError
    nil
  end

  def to_bool(value)
    return nil if value.nil?
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
