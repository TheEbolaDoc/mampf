# Media Helper
module MediaHelper
  # returns the array of all teachables, together with a string made up
  # from their class and id
  # Is used in options_for_select in form helpers.
  def all_teachables_selection(user)
    Course.editable_selection(user) + Lecture.editable_selection(user) +
      Lesson.editable_selection(user)
  end

  # does the current user have the right to edit the given medium?
  def medium_editor?(medium)
    current_user.admin || medium.edited_with_inheritance_by?(current_user)
  end

  def video_download_file(medium)
    medium.title + '.mp4'
  end

  def manuscript_download_file(medium)
    medium.title + '.pdf'
  end

  def inspect_or_edit_medium_path(medium, inspection)
    inspection ? inspect_medium_path(medium) : edit_medium_path(medium)
  end

  # create text for notification about new medium in notification dropdown menu
  def medium_notification_item_header(medium)
    return unless medium.proper?
    t('notifications.new_medium_in') + medium.teachable.media_scope.title_for_viewers
  end

  def medium_notification_item_details(medium)
    medium.local_title_for_viewers
  end

  # create text for notification about new medium in notification card
  def medium_notification_card_header(medium)
    teachable = medium.teachable
    if teachable.media_scope.class.to_s == 'Course'
      return link_to(teachable.media_scope.title_for_viewers,
                     course_path(medium.teachable.media_scope),
                     class: 'text-dark')
    end
    link_to(teachable.media_scope.title_for_viewers,
            medium.teachable.media_scope.path(current_user),
            class: 'text-dark')
  end

  # create link to medium in notification card
  def medium_notification_card_link(medium)
    link_to(medium.local_title_for_viewers,
            medium.becomes(Medium),
            class: 'darkblue')
  end

  def section_selection(medium)
    medium.teachable&.lecture&.section_selection
  end

  def preselected_sections(medium)
    return [] unless medium.teachable.class.to_s == 'Lesson'
    medium.teachable.sections.map(&:id)
  end


  def textcolor(medium)
    return '' if medium.visible?
    return 'locked' if medium.locked?
    'unpublished'
  end

  def infotainment(medium)
    return 'nichts' unless medium.video || medium.manuscript
    return 'ein Video' unless medium.manuscript
    return 'ein Manuskript' unless medium.video
    'ein Video und ein Manuskript'
  end

  def level_to_word(medium)
    return t('basics.not_set') unless medium.level.present?
    return t('basics.level_easy') if medium.level == 0
    return t('basics.level_medium') if medium.level == 1
    t('basics.level_hard')
  end

  def independent_to_word(medium)
    return t('basics.no_lc') unless medium.independent
    t('basics.yes_lc')
  end

  def medium_border(medium)
    return if medium.published? && !medium.locked?
    'border-danger'
  end

  def media_sorts_select(purpose)
    return add_prompt(Medium.select_quizzables) if purpose == 'quiz'
    return Medium.select_question if purpose == 'clicker'
    return add_prompt(Medium.select_importables) if purpose == 'import'
    add_prompt(Medium.select_sorts)
  end

  def sort_preselect(purpose)
    return '' unless purpose == 'quiz'
    'Question'
  end

  def search_results_label(purpose)
    prefix = if purpose == 'media'
               'media'
             elsif purpose == 'quiz'
               'quizzable'
             elsif purpose == 'clicker'
               'clickerizable'
             else
               'import'
             end
    prefix + 'SearchResults'
  end

  def search_result_id(purpose, medium)
    prefix = if purpose == 'media'
               'row-medium-'
             elsif purpose == 'quiz'
               'result-quizzable-'
             elsif purpose == 'clicker'
               'result-clickerizable-'
             else
               'result-import-'
             end
    prefix + medium.id.to_s
  end    

  def import_form(purpose)
    return '' unless purpose.in?(['quiz', 'import'])
    return 'importMediaForm' if purpose == 'import'
    'importVertexForm'
  end

  def preview_header(purpose)
    return '' unless purpose.in?(['quiz', 'import'])
    return 'importPreviewHeader' if purpose == 'import'
    'quizzesPreviewHeader'
  end

  def preview_main(purpose)
    return '' unless purpose.in?(['quiz', 'import'])
    return 'mediumPreview' if purpose == 'import'
    'quizzablePreview'
  end 
end
