require "csv"

class GalaxiesController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    scope = Galaxy.order(:name)
    if @query.present?
      like = "%#{@query.downcase}%"
      scope = scope.where("lower(name) LIKE :q OR lower(galaxy_type) LIKE :q", q: like)
    end
    @galaxies = scope
  end

  def show
    @galaxy = Galaxy.find(params[:id])
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
      attrs = row_to_attrs(row.to_h)
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
      :mag_u, :mag_g, :mag_r, :mag_i, :mag_z,
      :err_u, :err_g, :err_r, :err_i, :err_z,
      :extinction_u, :extinction_g, :extinction_r, :extinction_i, :extinction_z,
      :galaxy_type, :notes, :agn, :sdss_dr, :redshift_z, :sdss_objid, :source_catalog
    )
  end

  def row_to_attrs(row)
    attrs = {}
    attrs[:name] = value_for(row, "name")
    attrs[:ra] = to_float(value_for(row, "ra"))
    attrs[:dec] = to_float(value_for(row, "dec"))
    attrs[:mag_u] = to_float(value_for(row, "mag_u", "u"))
    attrs[:mag_g] = to_float(value_for(row, "mag_g", "g"))
    attrs[:mag_r] = to_float(value_for(row, "mag_r", "r"))
    attrs[:mag_i] = to_float(value_for(row, "mag_i", "i"))
    attrs[:mag_z] = to_float(value_for(row, "mag_z", "z"))
    attrs[:err_u] = to_float(value_for(row, "err_u"))
    attrs[:err_g] = to_float(value_for(row, "err_g"))
    attrs[:err_r] = to_float(value_for(row, "err_r"))
    attrs[:err_i] = to_float(value_for(row, "err_i"))
    attrs[:err_z] = to_float(value_for(row, "err_z"))
    attrs[:extinction_u] = to_float(value_for(row, "extinction_u"))
    attrs[:extinction_g] = to_float(value_for(row, "extinction_g"))
    attrs[:extinction_r] = to_float(value_for(row, "extinction_r"))
    attrs[:extinction_i] = to_float(value_for(row, "extinction_i"))
    attrs[:extinction_z] = to_float(value_for(row, "extinction_z"))
    attrs[:galaxy_type] = value_for(row, "galaxy_type", "type")
    attrs[:notes] = value_for(row, "notes")
    attrs[:agn] = to_bool(value_for(row, "agn"))
    attrs[:sdss_dr] = value_for(row, "sdss_dr")
    attrs[:redshift_z] = to_float(value_for(row, "redshift_z"))
    attrs[:sdss_objid] = value_for(row, "sdss_objid", "objid")
    attrs[:source_catalog] = value_for(row, "source_catalog")
    attrs.compact
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
