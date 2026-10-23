# frozen_string_literal: true

# A program grant a Knot received (see KnotGrants). Keyed to the Knot, never to
# the user, so it survives account deletion. It holds only the program key and
# the time: no amount, no reason, no name. The financial record of the grant
# is a different record with its own retention window.
# == Schema Information
#
# Table name: program_grants
# Database name: primary
#
#  id         :bigint           not null, primary key
#  granted_at :datetime         not null
#  program    :string           not null
#  knot_id    :bigint           not null
#
# Indexes
#
#  index_program_grants_on_knot_id              (knot_id)
#  index_program_grants_on_knot_id_and_program  (knot_id,program)
#
# Foreign Keys
#
#  fk_rails_...  (knot_id => knots.id)
#
class ProgramGrant < ApplicationRecord
  belongs_to :knot

  validates :program, inclusion: { in: ->(_) { KnotSettings.program_keys } }
  validates :granted_at, presence: true

  def program_name = KnotSettings.program(program)&.name || program

end
