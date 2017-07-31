# Course class
class Course < ApplicationRecord
  has_many :lectures
  has_many :course_tag_joins
  has_many :tags, through: :course_tag_joins
  has_many :assets, as: :teachable
  validates :title, presence: true, uniqueness: true

  def assets_in_lectures
    Asset.where(teachable: lectures)
  end

  def assets_in_lessons
    lessons = Lesson.where(lecture: lectures)
    Asset.where(teachable: lessons)
  end
end
