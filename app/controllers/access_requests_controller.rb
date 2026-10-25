# frozen_string_literal: true

# A member asks for access to a restricted app, and a group manager decides
# (see AccessRequests and AccessRequestPolicy).
#
# Deciding adds a member to a group, which is a grant of access, so an admin
# who impersonates a manager can't decide for them.
class AccessRequestsController < ApplicationController
  before_action :set_application, only: [:new, :create]
  before_action :set_request, only: [:approve, :deny]
  before_action :refuse_while_impersonating, only: [:approve, :deny]
  after_action :verify_authorized

  def new
    @access_request = AccessRequest.new(user: current_user, application: @application)
    authorize @access_request
    redirect_unless_requestable
  end

  def create
    authorize AccessRequest.new(user: current_user, application: @application)
    return if redirect_unless_requestable

    @access_request = AccessRequests.request!(user: current_user, application: @application,
                                              reason: params.dig(:access_request, :reason))
    if @access_request.persisted?
      redirect_to profile_path, notice: "Your request for #{@application.name} was sent. You get an email when someone decides."
    else
      render :new, status: :unprocessable_content
    end
  end

  def approve
    authorize @access_request
    AccessRequests.approve!(@access_request, by: current_user)
    redirect_to group_path(@access_request.group),
                notice: "#{@access_request.user.full_name} was added to #{@access_request.group.name} and can use #{@access_request.application.name}."
  rescue AccessRequests::Error, ActiveRecord::RecordInvalid => error
    redirect_to group_path(@access_request.group), alert: error.message
  end

  def deny
    authorize @access_request
    AccessRequests.deny!(@access_request, by: current_user)
    redirect_to group_path(@access_request.group), notice: "The request from #{@access_request.user.full_name} was denied."
  rescue AccessRequests::Error => error
    redirect_to group_path(@access_request.group), alert: error.message
  end

  private

  def set_application
    application_id = params[:application].presence || params.dig(:access_request, :application)
    @application = Doorkeeper::Application.find_by_public_param!(application_id)
  end

  def set_request
    @access_request = AccessRequest.find_by_public_param!(params[:id])
  end

  # Sends the member back with the reason they can't ask. Returns true when
  # it redirected.
  def redirect_unless_requestable
    return false if AccessRequests.requestable?(current_user, @application)

    if AppAccess.permitted?(current_user, @application)
      redirect_to profile_path, notice: "You already have access to #{@application.name}."
    elsif AccessRequests.pending_for(current_user, @application)
      redirect_to profile_path, notice: "You already asked for access to #{@application.name}. You get an email when someone decides."
    else
      redirect_to profile_path, alert: "You can't ask for access to #{@application.name} here. Ask a Weave admin."
    end
    true
  end

  def refuse_while_impersonating
    return unless impersonating?

    redirect_to group_path(@access_request.group), alert: "You can't decide access requests while impersonating a user."
  end

end
