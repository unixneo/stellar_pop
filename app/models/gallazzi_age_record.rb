class GallazziAgeRecord < ApplicationRecord
  self.abstract_class = true

  establish_connection :"gallazzi_age_#{Rails.env}"
end
