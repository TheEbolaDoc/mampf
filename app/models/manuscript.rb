# Manuscript class
# plain old ruby class, no active record involved
class Manuscript
  include ActiveModel::Model

  attr_reader :medium, :lecture, :chapters, :sections, :content,
              :contradictions, :contradiction_count

  def initialize(medium)
    unless medium && medium.sort == 'Script' &&
             medium&.teachable_type == 'Lecture' &&
             medium.manuscript && medium.manuscript[:original]
      return
    end
    @medium = medium
    @lecture = medium.teachable.lecture
    bookmarks = medium.manuscript[:original].metadata['bookmarks'] || []
    @chapters = get_chapters(bookmarks)
    match_mampf_chapters
    @sections = get_sections(bookmarks)
    match_mampf_sections
    @content = get_content(bookmarks)
    check_content
    @contradictions = get_contradictions
    @contradiction_count = @contradictions['chapters'].size +
                             @contradictions['sections'].size +
                             @contradictions['content'].size +
                             @contradictions['multiplicities'].size
  end

  def empty?
    @medium.nil?
  end

  def sections_in_chapter(chapter)
    @sections.select { |s| s['chapter'] == chapter['chapter'] }
             .sort_by { |s| s['counter'] }
  end

  def content_in_section(section)
    @content.select { |c| c['section'] == section['section'] }
            .sort_by { |c| c['counter'] }
  end

  # returns those content bookmarks who have a chapter or section counter
  # that corresponds to a chapter or section without a bookmark
  def content_in_unbookmarked_locations
    @content.select { |c| c['contradiction'] }
  end

  def content_in_unbookmarked_locations?
    @content.any? { |c| c['contradiction'] }
  end

  def sections_in_unbookmarked_chapters
    @sections.select { |s| s['contradiction'] == :missing_chapter }
  end

  def sections_in_unbookmarked_chapters?
    @sections.any? { |s| s['contradiction'] == :missing_chapter }
  end

  # returns the matching chapter in mampf for the given manuscript chapter
  # (matching is done by label)
  def chapter_in_mampf(chapter)
    @lecture&.chapters
             .find { |chap| chap.reference == chapter['label'] }
  end

  def section_in_mampf(section)
    @lecture&.sections
             .find { |sec| sec.reference == section['label'] }
  end

  def manuscript_chapter_contradicts?(chapter)
    chapter_in_mampf(chapter)&.title != chapter['description']
  end

  def export_to_db!
    return unless @contradiction_count.zero?
    create_new_chapters!
    @chapters.each do |c|
      create_new_sections!(c)
      c['mampf_chapter'] = c['mampf_chapter'].reload
    end
    create_chapter_items!
    create_section_items!
    create_content_items!
  end

  def unmatched_mampf_chapters
    chapters_in_mampf = @chapters.map { |c| c['mampf_chapter'] }.compact
    @lecture.chapters - chapters_in_mampf
  end

  def unmatched_mampf_sections
    sections_in_mampf = @sections.map { |s| s['mampf_section'] }.compact
    @lecture.sections - sections_in_mampf
  end

  def new_chapters
    @chapters.select { |c| c['mampf_chapter'].nil? }
             .map { |c| [c['new_position'], c['description'], c['counter']] }
  end

  def create_new_chapters!
    new_chapters.each do |c|
      chap = Chapter.new(lecture_id: @lecture.id, title: c.second)
      chap.insert_at(c.first)
      corresponding = @chapters.find { |d| d['counter'] == c.third }
      corresponding['mampf_chapter'] = chap
    end
    @lecture = @lecture.reload
  end

  def new_sections_in_chapter(chapter)
    sections = sections_in_chapter(chapter)
    sections.each_with_index
            .map { |s,i| [s['mampf_section'], i+1, s['description'], s['counter']] }
            .select { |s| s.first.nil? }
            .map { |s| [s.second, s.third, s.fourth] }
  end

  def create_new_sections!(chapter)
    return if chapter['mampf_chapter'].nil?
    mampf_chapter = chapter['mampf_chapter']
    new_sections_in_chapter(chapter).each do |s|
      sect = Section.new(chapter_id: mampf_chapter.id, title: s.second)
      sect.insert_at(s.first)
      corresponding = @sections.find { |d| d['counter'] == s.third }
      corresponding['mampf_section'] = sect
    end
  end

  def sections_with_content
    @sections.select { |s| content_in_section(s).present? }
  end

  def sections_without_content
    @lecture.sections - sections_with_content
  end

  def create_chapter_items!
    @chapters.each do |c|
      # check if there exists an item with this destination in this medium
      # if so, only update
      item = Item.where(medium: @medium,
                        pdf_destination: c['destination'])
                  &.first
      if item
        item.update(sort: 'chapter',
                    page: c['page'],
                    description: c['description'],
                    ref_number: c['label'],
                    position: nil,
                    section_id: nil,
                    start_time: nil)
        next
      end
      Item.create(medium_id: @medium.id,
                  section_id: nil,
                  sort: 'chapter',
                  page: c['page'],
                  description: c['description'],
                  ref_number: c['label'],
                  pdf_destination: c['destination'])
    end
  end

  def create_section_items!
    @sections.each do |s|
      # check if there exists an item with this destination in this medium
      # if so, only update
      item = Item.where(medium: @medium,
                        pdf_destination: s['destination'])
                  &.first
      if item
        item.update(section_id: s['mampf_section'].id,
                    sort: 'section',
                    page: s['page'],
                    description: s['description'],
                    ref_number: s['label'],
                    position: nil,
                    section_id: s['mampf_section'].id,
                    start_time: nil)
        next
      end
      Item.create(medium_id: @medium.id,
                  section_id: s['mampf_section'].id,
                  sort: 'section',
                  page: s['page'],
                  description: s['description'],
                  ref_number: s['label'],
                  pdf_destination: s['destination'])
    end
  end

  def create_content_items!
    sections_with_content.each do |s|
      content_in_section(s).each do |c|
        # check if there exists an item with this destination in this medium
        # if so, only update
        item = Item.where(medium: @medium,
                          pdf_destination: c['destination'])
                  &.first
        if item
          item.update(section_id: s['mampf_section'].id,
                      sort: Item.internal_sort(c['sort']),
                      page: c['page'], description: c['description'],
                      ref_number: c['label'], position: c['counter'],
                      start_time: nil)
          next
        end
        Item.create(medium_id: @medium.id, section_id: s['mampf_section'].id,
                    sort: Item.internal_sort(c['sort']),
                    page: c['page'],
                    description: c['description'], ref_number: c['label'],
                    position: c['counter'], pdf_destination: c['destination'])
      end
    end
  end

  def destinations_with_multiplicities
    bookmarks = @medium.manuscript[:original].metadata['bookmarks'] || []
    destinations = bookmarks.map { |b| b['destination'] }
    destinations.each_with_object(Hash.new(0)) do |word,counts|
      counts[word] += 1
    end
  end

  def destinations_with_higher_multiplicities
    destinations_with_multiplicities.select { |k,v| v > 1 }.keys
  end

  private

  def get_chapters(bookmarks)
    bookmarks.select { |b| b['sort'] == 'Kapitel' }
             .map { |c| c.slice('label', 'chapter', 'description', 'counter',
                                'destination', 'page') }
             .sort_by { |c| c['counter'] }
             .each_with_index { |c,i| c['new_position'] = i + 1 }
  end

  def get_sections(bookmarks)
    bookmarks.select { |b| b['sort'] == 'Abschnitt' }
              .map { |s| s.slice('label', 'section', 'description', 'chapter',
                                 'counter', 'destination', 'page') }
              .sort_by { |s| s['counter'] }
  end

  def get_content(bookmarks)
    bookmarks.select { |b| !b['sort'].in?(['Kapitel', 'Abschnitt']) }
             .map { |c| c.slice('sort','label', 'description',
                                'chapter', 'section', 'counter', 'destination',
                                'page') }
             .sort_by { |c| c['counter'] }
  end

  def match_mampf_chapters
    @chapters.each do |c|
      mampf_chapter = chapter_in_mampf(c)
      c['mampf_chapter'] = mampf_chapter
      c['contradiction'] = if mampf_chapter.nil? || mampf_chapter.title == c['description']
                             false
                           else
                             :different_title
                           end
    end
  end

  def match_mampf_sections
    @sections.each do |s|
      bookmarked_chapter_counters = @chapters.map { |c| c['chapter'] }
      if !s['chapter'].in?(bookmarked_chapter_counters)
        s['mampf_section'] = nil
        s['contradiction'] = :missing_chapter
        next
      end
      mampf_section = section_in_mampf(s)
      s['mampf_section'] = mampf_section
      s['contradiction'] = if mampf_section.nil? || mampf_section.title == s['description']
                             false
                           else
                             :different_title
                           end
    end
  end

  def check_content
    bookmarked_section_counters = @sections.map { |s| s['section'] }
    bookmarked_chapter_counters = @chapters.map { |c| c['chapter'] }
    @content.each do |c|
      if !c['chapter'].in?(bookmarked_chapter_counters)
        c['contradiction'] = :missing_chapter
      elsif !c['section'].in?(bookmarked_section_counters)
        c['contradiction'] = :missing_section
      else
        c['contradiction'] = false
      end
    end
  end

  def get_contradictions
    { 'chapters' => @chapters.select { |c| c['contradiction'] },
      'sections' => @sections.select { |s| s['contradiction'] },
      'content' => @content.select { |c| c['contradiction'] },
      'multiplicities' => destinations_with_higher_multiplicities }
  end
end