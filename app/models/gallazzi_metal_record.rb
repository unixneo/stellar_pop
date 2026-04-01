class GallazziMetalRecord < ApplicationRecord
  self.abstract_class = true

  establish_connection :"gallazzi_metal_#{Rails.env}"
end
