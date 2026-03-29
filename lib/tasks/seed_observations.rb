require "yaml"

benchmarks_path = Rails.root.join("lib/data/calibration/benchmarks.yml")
payload = YAML.safe_load(File.read(benchmarks_path), permitted_classes: [], aliases: false) || {}
benchmarks = Array(payload["benchmarks"])

created = 0
updated = 0
skipped = 0

benchmarks.each do |benchmark|
  name = benchmark["name"].to_s
  galaxy = Galaxy.find_by(name: name)

  unless galaxy
    puts "Skipping #{name}: galaxy not found"
    skipped += 1
    next
  end

  expected = benchmark["expected"] || {}
  age_min = expected["age_gyr_min"]
  age_max = expected["age_gyr_max"]
  z_min = expected["metallicity_z_min"]
  z_max = expected["metallicity_z_max"]

  age_gyr =
    if !age_min.nil? && !age_max.nil?
      (age_min.to_f + age_max.to_f) / 2.0
    end

  metallicity_z =
    if !z_min.nil? && !z_max.nil?
      (z_min.to_f + z_max.to_f) / 2.0
    end

  method_used = benchmark["benchmark_type"]
  notes = benchmark["notes"]

  Array(benchmark["references"]).each do |source_paper|
    observation = Observation.find_or_initialize_by(
      galaxy_id: galaxy.id,
      source_paper: source_paper.to_s
    )

    was_new = observation.new_record?
    observation.assign_attributes(
      age_gyr: age_gyr,
      metallicity_z: metallicity_z,
      stellar_mass: nil,
      sfr: nil,
      method_used: method_used,
      notes: notes
    )
    observation.save!

    if was_new
      created += 1
    else
      updated += 1
    end
  end
end

puts "Seed observations complete: created=#{created}, updated=#{updated}, skipped=#{skipped}"
