class Api::V1::MediaController < ApplicationController
  respond_to :json
  def keks_question
    @medium = Medium.KeksQuestion.find_by(question_id: params[:id])
    render :json => @medium, width: params[:width]
  end
end