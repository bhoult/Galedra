# Switch every runtime PostgreSQL connection to the restricted application role
# (Ledger::DatabaseRole). Owner-level work (migrations, schema loads) is
# detected and left on the connecting user.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  prepend(Module.new do
    private

    def configure_connection
      super
      return unless Ledger::DatabaseRole.switch?

      internal_execute("SET ROLE #{Ledger::DatabaseRole::ROLE}", "SCHEMA")
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.cause.is_a?(PG::UndefinedObject)

      raise ActiveRecord::StatementInvalid,
            "database role #{Ledger::DatabaseRole::ROLE} is missing; run bin/rails db:prepare (#{e.message.strip})"
    end
  end)
end
