# ProfileController
class ProfileController < ApplicationController
  before_action :set_user
  before_action :set_basics, only: [:update]

  def edit
    # ensure that users do not have a blank name
    @user.update(name: @user.name || @user.email.split('@').first)
    redirect_to consent_profile_path unless @user.consents
    # destroy the notifications related to new lectures and courses
    current_user.notifications.where(notifiable_type: ['Lecture', 'Course'])
                .destroy_all
  end

  def update
    if @user.update(lectures: @lectures, courses: @courses, name: @name,
                    subscription_type: @subscription_type,
                    no_notifications: @no_notifications,
                    edited_profile: true)
      # remove notifications that have become obsolete
      clean_up_notifications
      # add details about users's subscribed courses to CourseUserJoin
      add_details
      # update current course cookie if current cookie refers to a
      # course that was unsubscribed
      unless @user.courses.map(&:id).include?(cookies[:current_course].to_i)
        cookies[:current_course] = @courses.first.id
      end
      redirect_to :root, notice: 'Profil erfolgreich geupdatet.'
    else
      @errors = @user.errors
    end
  end

  # this is triggered after every sign in
  # if profile has never been edited user is redirected
  def check_for_consent
    if @user.consents && @user.edited_profile
      redirect_to :root
      return
    end
    return unless @user.consents
    redirect_to edit_profile_path,
                notice: 'Bitte nimm Dir ein paar Minuten Zeit, um Dein ' \
                        'Profil zu bearbeiten.'
  end

  # DSGVO consent action
  def add_consent
    @user.update(consents: true, consented_at: Time.now)
    redirect_to :root, notice: 'Einwilligung zur Speicherung und Verarbeitung'\
                                'von Daten wurde erklärt.'
  end

  private

  def set_user
    @user = current_user
  end

  def set_basics
    @subscription_type = params[:user][:subscription_type].to_i
    @name = params[:user][:name]
    @no_notifications = params[:user][:no_notifications] == '1'
    @courses = Course.where(id: course_ids)
    @lectures = Lecture.where(id: lecture_ids)
  end

  # extracts all course ids from user params
  def course_ids
    filter_by('course')
  end

  # extracts all lecture ids (primary and secondary) from user params
  def lecture_ids
    primary + secondary
  end

  # extracts primary lecture from user params
  def primary
    params[:user].keys.select { |k| k.start_with?('primary_lecture-') }
                 .reject { |c| params[:user][c] == '0' }
                 .map { |c| params[:user][c] }.map(&:to_i)
  end

  # extracts secondary lectures from user params
  def secondary
    filter_by('lecture')
  end

  # extracts selected (secondary) lectures/courses (given as type)
  # from user params
  def filter_by(type)
    params[:user].keys.select { |k| k.start_with?(type + '-') }
                 .select { |c| params[:user][c] == '1' }
                 .map { |c| c.remove(type + '-').to_i }
  end

  # for each subscribed course, add details about current user's extras
  def add_details
    @courses.each do |c|
      details = CourseUserJoin.where(user: @user, course: c).first
      details.update(c.extras(params[:user]))
    end
  end

  def clean_up_notifications
    # delete all of the user's notifications if he does not want them
    # @user.notifications.delete_all if @no_notifications
    # remove all notification related not related to subscribed courses
    # or lectures
    subscribed_teachables = @courses + @lectures
    irrelevant_notifications = @user.notifications.select do |n|
      n.teachable.present? && !n.teachable.in?(subscribed_teachables)
    end
    Notification.where(id: irrelevant_notifications.map(&:id)).delete_all
  end
end
