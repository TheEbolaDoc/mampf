# Medium class
class Medium < ApplicationRecord
  include ApplicationHelper
  include ActiveModel::Dirty
  belongs_to :teachable, polymorphic: true
  has_many :medium_tag_joins, dependent: :destroy
  has_many :tags, through: :medium_tag_joins
  has_many :links, dependent: :destroy
  has_many :linked_media, through: :links
  has_many :editable_user_joins, as: :editable, dependent: :destroy
  has_many :editors, through: :editable_user_joins, as: :editable,
                     source: :user
  has_many :items, dependent: :destroy
  has_many :referrals, dependent: :destroy
  has_many :referenced_items, through: :referrals, source: :item
  include VideoUploader[:video]
  include ImageUploader[:screenshot]
  include PdfUploader[:manuscript]
  validates :sort, presence: { message: 'Es muss ein Typ angegeben werden.'}
  validates :external_reference_link, http_url: true,
                                      if: :external_reference_link?
  validates :teachable, presence: { message: 'Es muss eine Assoziation ' \
                                            'angegeben werden.'}
  validates :description, presence: { message: 'Es muss eine Beschreibung' \
                                               'angegeben werden.' },
                          unless: :undescribable?
  validates :editors, presence: { message: 'Es muss ein Editor ' \
                                           'angegeben werden.'}
  after_save :touch_teachable
  after_create :create_self_item

  def self.sort_enum
    %w[Kaviar Erdbeere Sesam Kiwi Reste KeksQuestion KeksQuiz]
  end

  def self.search(primary_lecture, params)
    course = Course.find_by_id(params[:course_id])
    return [] if course.nil?
    filtered = Medium.filter_media(course, params[:project])
    unless params[:lecture_id].present?
      return search_results(filtered, course, primary_lecture)
    end
    lecture = Lecture.find_by_id(params[:lecture_id].to_i)
    return [] unless course.lectures.include?(lecture)
    lecture.lecture_lesson_results(filtered)
  end

  def self.select_by_name
    Medium.includes(:teachable).all.map { |m| [m.title, m.id] }
  end

  def protected_items
    pdf_items = Item.where(medium: self, sort: 'pdf_destination')
    referred_items = Referral.where(item: pdf_items).map(&:item)
    referencing_items = proper_items.select do |i|
      i.pdf_destination.in?(pdf_items.map(&:pdf_destination))
    end
    destination_items = Item.where(medium: self, sort: 'pdf_destination',
                                   pdf_destination: referencing_items.map(&:pdf_destination))
    (referred_items + destination_items).to_a.uniq
  end

  def create_pdf_destinations!
    manuscript_destinations.each do |d|
      unless Item.exists?(medium: self, sort: 'pdf_destination',
                          description: d, pdf_destination: d)
        Item.create(medium: self, sort: 'pdf_destination', description: d,
                    pdf_destination: d)
      end
    end
  end

  def update_pdf_destinations!
    items_to_conserve = protected_items
    create_pdf_destinations!
    items_to_destroy = Item.where(medium: self, sort: 'pdf_destination')
                           .reject do |i|
      i.pdf_destination.in?(manuscript_destinations) ||
      i.in?(items_to_conserve)
    end
    items_to_destroy.each(&:destroy)
  end

  def destroy_pdf_destinations!(destinations)
    Item.where(medium: self, sort: 'pdf_destination',
               pdf_destination: destinations).each(&:destroy)
    proper_items.where(pdf_destination: destinations)
                .each do |i|
      i.update(pdf_destination: nil)
    end
  end

  def edited_by?(user)
    return true if editors.include?(user)
    false
  end

  def edited_with_inheritance_by?(user)
    return true if editors.include?(user)
    return true if teachable.lecture&.editors&.include?(user)
    return true if teachable.course.editors&.include?(user)
    false
  end

  def toc_to_vtt
    path = toc_path
    File.open(path, 'w+:UTF-8') do |f|
      f.write vtt_start
      proper_items_by_time.each do |i|
        f.write i.vtt_time_span
        f.write i.vtt_reference
      end
    end
    path
  end

  def references_to_vtt
    path = references_path
    File.open(path, 'w+:UTF-8') do |f|
      f.write vtt_start
      referrals_by_time.each do |r|
        f.write r.vtt_time_span
        f.write JSON.pretty_generate(r.vtt_properties) + "\n\n"
      end
    end
    path
  end

  def proper_items
    items.where.not(sort: ['self', 'pdf_destination'])
  end

  def proper_items_by_time
    proper_items.to_a.sort do |i, j|
      i.start_time.total_seconds <=> j.start_time.total_seconds
    end
  end

  def referrals_by_time
    referrals.to_a.sort do |r, s|
      r.start_time.total_seconds <=> s.start_time.total_seconds
    end
  end

  def manuscript_pages
    return unless manuscript.present?
    manuscript[:original].metadata["pages"]
  end

  def screenshot_url
    return unless screenshot.present?
    screenshot.url(host: host)
  end

  def video_url
    return unless video.present?
    video.url(host: host)
  end

  def video_download_url
    video.url(host: download_host)
  end

  def video_filename
    return unless video.present?
    video.metadata['filename']
  end

  def video_size
    return unless video.present?
    video.metadata['size']
  end

  def video_resolution
    return unless video.present?
    video.metadata['resolution']
  end

  def video_duration
    return unless video.present?
    video.metadata['duration']
  end

  def video_duration_hms_string
    return unless video.present?
    TimeStamp.new(total_seconds: video_duration).hms_string
  end

  def manuscript_url
    return unless manuscript.present?
    manuscript[:original].url(host: host)
  end

  def manuscript_download_url
    manuscript[:original].url(host: download_host)
  end

  def manuscript_filename
    return unless manuscript.present?
    manuscript[:original].metadata['filename']
  end

  def manuscript_size
    return unless manuscript.present?
    manuscript[:original].metadata['size']
  end

  def manuscript_screenshot_url
    return unless manuscript.present?
    manuscript[:screenshot].url(host: host)
  end

  def manuscript_destinations
    return [] unless manuscript.present?
    if manuscript.class.to_s == 'PdfUploader::UploadedFile'
      return manuscript.metadata['destinations'] || []
    end
    if manuscript.class.to_s == 'Hash' && manuscript.keys == [:original, :screenshot]
      return manuscript[:original].metadata['destinations'] || []
    end
  end

  def video_width
    return unless video.present?
    video_resolution.split('x')[0].to_i
  end

  def video_height
    return unless video.present?
    video_resolution.split('x')[1].to_i
  end

  def video_aspect_ratio
    return unless video_height != 0 && video_width != 0
    video_width.to_f / video_height
  end

  def video_scaled_height(new_width)
    return unless video_height != 0 && video_width != 0
    (new_width.to_f / video_aspect_ratio).to_i
  end

  def caption
    return description if description.present?
    return '' unless sort == 'Kaviar' && teachable_type == 'Lesson'
    teachable.section_titles || ''
  end

  def card_header
    teachable.card_header
  end

  def card_header_teachable_path(user)
    teachable.card_header_path(user)
  end

  def card_subheader
    sort_de
  end

  def sort_de
    { 'Kaviar' => 'KaViaR', 'Sesam' => 'SeSAM',
      'KeksQuestion' => 'Keks-Frage', 'KeksQuiz' => 'Keks-Quiz',
      'Reste' => 'RestE', 'Erdbeere' => 'ErDBeere', 'Kiwi' => 'KIWi' }[sort]
  end

  def related_to_lecture?(lecture)
    return true if belongs_to_course?(lecture)
    return true if belongs_to_lecture?(lecture)
    return true if belongs_to_lesson?(lecture)
    false
  end

  def related_to_lectures?(lectures)
    lectures.map { |l| related_to_lecture?(l) }.include?(true)
  end

  def course
    return if teachable.nil?
    teachable.course
  end

  def lecture
    return if teachable.nil?
    teachable.lecture
  end

  def lesson
    return if teachable.nil?
    teachable.lesson
  end

  def self.filter_media(course, project)
    return Medium.order(:id) unless project.present?
    return [] unless course.available_food.include?(project)
    sort = project == 'keks' ? 'KeksQuiz' : project.capitalize
    Medium.where(sort: sort).order(:id)
  end

  def self.search_results(filtered_media, course, primary_lecture)
    course_results = filtered_media.select { |m| m.teachable == course }
    # media associated to primary lecture and its lessons
    primary_results = Medium.filter_primary(filtered_media, primary_lecture)
    # media associated to the course, all of its lectures and their lessons
    secondary_results = Medium.filter_secondary(filtered_media, course)
    # throw out media that have appeared as one of the above two types
    secondary_results = secondary_results - course_results - primary_results
    # differentiate primary results whether they are associated to the lecture
    # or a lesson of it
    primary_lecture_results = Medium.filter_by_lecture(primary_results)
    primary_lessons_results = primary_results - primary_lecture_results
    # sort them in the following way
    # - course results, by caption
    # - primary lecture results, by caption
    # - primary lesson results, by date
    # - secondary results
    course_results.natural_sort_by(&:caption) +
      primary_lecture_results.natural_sort_by(&:caption) +
      primary_lessons_results.sort_by { |m| m.teachable.date } +
      secondary_results
  end

  def self.filter_primary(filtered_media, primary_lecture)
    return [] unless primary_lecture.present?
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.lecture == primary_lecture
    end
  end

  def self.filter_by_lecture(media)
    media.select { |m| m.teachable_type == 'Lecture' }
  end

  def self.filter_secondary(filtered_media, course)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.course == course
    end
  end

  def irrelevant?
    video.nil? && manuscript.nil? && external_reference_link.blank?
  end

  def teachable_select
    teachable_type + '-' + teachable_id.to_s
  end

  def question_id
    return unless sort == 'KeksQuestion'
    external_reference_link.remove(DefaultSetting::KEKS_QUESTION_LINK).to_i
  end

  def question_ids
    return unless sort == 'KeksQuiz'
    external_reference_link.remove(DefaultSetting::KEKS_QUESTION_LINK)
                           .split(',').map(&:to_i)
  end

  def position
    teachable.media.where(sort: self.sort).order(:id).index(self)  + 1
  end

  def siblings
    teachable.media.where(sort: self.sort)
  end

  def compact_info
    compact_info = sort_de + '.' + teachable.compact_title
    return compact_info unless siblings.count > 1
    compact_info + '.(' + position.to_s + '/' + siblings.count.to_s + ')'
  end

  def local_info
    return description if description.present?
    return 'ohne Titel' unless undescribable?
    return "zu Sitzung #{teachable.lesson&.number&.to_s}, #{teachable.lesson&.date_de}" if sort == 'Kaviar'
    'KeksFrage ' + position.to_s + '/' + siblings.count.to_s
  end

  def details
    return description if description.present?
    return 'Frage ' + question_id.to_s if sort == 'KeksQuestion'
    return 'Fragen ' + question_ids.join(', ') if sort == 'KeksQuiz'
    ''
  end

  def title
    return compact_info if details.blank?
    compact_info + '.' + details
  end

  def title_for_viewers
    sort_de + ', ' + teachable.title_for_viewers +
      (description.present? ? ', ' + description : '')
  end

  def local_title_for_viewers
    if  sort == 'Kaviar' && teachable.class.to_s == 'Lesson'
      return 'KaViaR, ' + teachable.local_title_for_viewers
    end
    sort_de + (description.present? ? ', ' + description : ', ohne Titel')
  end

  scope :KeksQuestion, -> { where(sort: 'KeksQuestion') }
  scope :Kaviar, -> { where(sort: 'Kaviar') }

  def items_with_references
    Rails.cache.fetch("#{cache_key}/items_with_reference") do
      items.map { |i| { id: i.id,
                        title_within_course: i.title_within_course,
                        title_within_lecture: i.title_within_lecture
                        } }
    end
  end

  def reset_pdf_destinations
    Item.where(medium: self, sort: 'pdf_destination').each(&:destroy)
    manuscript_destinations.each do |d|
      Item.create(medium: self, sort: 'pdf_destination', description: d)
    end
  end

  private

  def undescribable?
    (sort == 'Kaviar' && teachable.class.to_s == 'Lesson') || sort == 'KeksQuestion'
  end

  def touch_teachable
    return if teachable.nil?
    if teachable.course.present? && teachable.course.persisted?
      teachable.course.touch
    end
    optional_touches
  end

  def optional_touches
    if teachable.lecture.present? && teachable.lecture.persisted?
      teachable.lecture.touch
    end
    if teachable.lesson.present? && teachable.lesson.persisted?
      teachable.lesson.touch
    end
  end

  def toc_path
    Rails.root.join('public', 'tmp').to_s + '/toc-' + SecureRandom.hex + '.vtt'
  end

  def references_path
    Rails.root.join('public', 'tmp').to_s + '/ref-' + SecureRandom.hex + '.vtt'
  end

  def vtt_start
    "WEBVTT\n\n"
  end

  def belongs_to_course?(lecture)
    teachable_type == 'Course' && teachable == lecture.course
  end

  def belongs_to_lecture?(lecture)
    teachable_type == 'Lecture' && teachable == lecture
  end

  def belongs_to_lesson?(lecture)
    teachable_type == 'Lesson' && teachable.lecture == lecture
  end

  def filter_primary(filtered_media, primary_lecture)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.lecture == primary_lecture
    end
  end

  def filter_secondary(filtered_media, course)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.course == course
    end
  end

  def create_self_item
    Item.create(sort: 'self', medium: self)
  end

  def local_items
    return teachable.items - items if teachable_type == 'Course'
    teachable.lecture.items - items
  end
end
