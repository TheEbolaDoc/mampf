# ApplicationHelper module
module ApplicationHelper

  def host
    Rails.env.production? ? ENV['MEDIA_SERVER'] + '/' + ENV['MEDIA_FOLDER'] : ''
  end

  def download_host
    Rails.env.production? ? ENV['DOWNLOAD_LOCATION'] : ''
  end

  # Returns the full title on a per-page basis.
  def full_title(page_title = '')
    base_title = 'MaMpf'
    if page_title.empty?
      base_title
    else
      base_title + ' | ' + page_title
    end
  end

  def hide(value)
    value ? 'none;' : 'block;'
  end

  def show(value)
    value ? 'block;' : 'none;'
  end

  def show_inline(value)
    value ? 'inline;' : 'none;'
  end

  def show_no_block(value)
    value ? '' : 'none;'
  end

  def active(value)
    value ? 'active' : ''
  end

  def show_collapse(value)
    value ? 'show collapse' : 'collapse'
  end

  def show_tab(value)
    value ? 'show active' : ''
  end

  def media_types
    { 'kaviar' => ['Kaviar'], 'sesam' => ['Sesam'],
      'keks' => ['KeksQuiz', 'KeksQuestion'], 'kiwi' => ['Kiwi'],
      'erdbeere' => ['Erdbeere'], 'reste' => ['Reste'] }
  end

  def media_sorts
    ['kaviar', 'sesam', 'keks', 'kiwi', 'erdbeere', 'reste']
  end

  def media_names
    { 'kaviar' => 'KaViaR', 'sesam' => 'SeSAM',
      'keks' => 'KeKs', 'kiwi' => 'KIWi',
      'erdbeere' => 'ErDBeere', 'reste' => 'RestE' }
  end

  def lecture_media(media)
    media.select { |m| m.teachable_type.in?(['Lecture', 'Lesson']) }
  end

  def course_media(media)
    media.select { |m| m.teachable_type == 'Course' }
  end

  def lecture_course_teachables(media)
    lecture_ids =  lecture_media(media).map { |m| m.teachable.lecture }
                                       .map(&:id).uniq
    course_ids = course_media(media).map { |m| m.teachable.course }
                                    .map(&:id).uniq
    lectures = Lecture.where(id: lecture_ids)
    courses = Course.where(id: course_ids)
    courses + lectures
  end

  def relevant_media(teachable, media)
    if teachable.class == Course
      return course_media(media).select { |m| m.course == teachable }
    end
    lecture_media(media).select { |m| m.teachable.lecture == teachable }
  end

  def split_list(list, pieces = 4)
    group_size = (list.count / pieces) != 0 ? list.count / pieces : 1
    groups = list.in_groups_of(group_size)
    diff = groups.count - pieces
    return groups if diff <= 0
    tail = groups.pop(diff).first(diff).flatten
    groups.last.concat(tail)
    groups
  end

  def course_id_from_cookie
    return cookies[:current_course].to_i unless cookies[:current_course].nil?
    return if current_user.nil?
    return current_user.courses.first.id unless current_user.courses.empty?
  end

  def thyme?(controller, action)
    return true if controller == 'media' && action == 'play'
    false
  end

  def enrich?(controller, action)
    return true if controller == 'media' && action == 'enrich'
    false
  end

  def administrates?(controller, action)
    return true if controller.in?(['administration', 'terms', 'lectures'])
    return true if controller == 'courses' && action != 'show'
    return true if controller == 'users' && action != 'teacher'
    return true if controller == 'tags' && action != 'show'
    return true if controller == 'chapters' && action != 'show'
    return true if controller == 'sections' && action != 'show'
    return true if controller == 'lessons' && action != 'show'
    return true if controller == 'media' && action != 'show' && action != 'index'
    false
  end

  def inspect_teachable_path(teachable)
    return inspect_course_path(teachable) if teachable.class.to_s == 'Course'
    return inspect_lecture_path(teachable) if teachable.class.to_s == 'Lecture'
    inspect_lesson_path(teachable)
  end

  def long_title(teachable)
    return teachable.title if teachable.class.to_s.in?(['Course', 'Lecture'])
    return teachable.long_title
  end

  def shorten(title, max_letters)
    return '' unless title.present?
    return title unless title.length > max_letters
    title[0, max_letters - 3] + '...'
  end


  def thyme_caption(medium)
    medium.sort_de + ' ' + long_title(medium.teachable) + ' ' +
      (medium.description || '')
  end

  def grouped_teachable_list
    list = []
    Course.all.each do |c|
      lectures = [[c.short_title + ' alle', 'Course-' + c.id.to_s]]
      c.lectures.includes(:term).each do |l|
        lectures.push [l.short_title, 'Lecture-' + l.id.to_s]
      end
      list.push [c.title, lectures]
    end
    list.push [ 'externe Referenzen', [['extern alle', 'external-0']]]
  end
end
