# frozen_string_literal: true

# The base of every Pundit policy. Every action is refused unless a policy
# allows it (fail-closed), and every Scope is empty unless it says otherwise.
#
# `user` is always a User (the signed-in member, or the member an admin
# impersonates), or nil. Keep it that way: one kind of policy user only.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = false

  def show? = false

  def create? = false

  def new? = create?

  def update? = false

  def edit? = update?

  def destroy? = false

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve = scope.none

    private

    attr_reader :user, :scope

  end

end
