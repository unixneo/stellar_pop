class AddMagTypeToPipelineConfigs < ActiveRecord::Migration[7.1]
  def up
    add_column :pipeline_configs, :mag_type, :string, default: "petrosian", null: false
  end

  def down
    remove_column :pipeline_configs, :mag_type
  end
end
