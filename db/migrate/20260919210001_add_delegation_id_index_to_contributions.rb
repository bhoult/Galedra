# Contributors::Tally joins contributions to agent_delegations through
# envelope->>'delegation_id', which no index covered, so crediting an agent's
# work to the person it acts for meant a sequential scan of the whole log
# (Stage 26).
#
# An expression index rather than a column: the delegation id lives inside the
# signed envelope, and denormalising it onto the log's own table would add a
# column to the one table this project is most careful about. An index is
# derived data, like every projection, and can be dropped and rebuilt.
class AddDelegationIdIndexToContributions < ActiveRecord::Migration[8.1]
  def change
    add_index :contributions, "(envelope->>'delegation_id')", name: "index_contributions_on_envelope_delegation_id"
  end
end
