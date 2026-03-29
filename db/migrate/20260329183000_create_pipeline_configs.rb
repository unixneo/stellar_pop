class CreatePipelineConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_configs do |t|
      t.text :settings_json, null: false, default: "{}"

      t.timestamps
    end
  end
end
