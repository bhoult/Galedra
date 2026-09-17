# frozen_string_literal: true

module Ledger
  # The database role the application runs as (spec 02 §5, 10 "DB permissions"):
  # it can never DELETE or TRUNCATE contributions and can UPDATE only
  # current_status. Migrations and schema loads run as the connecting owner;
  # runtime connections switch with SET ROLE (see config/initializers/ledger.rb).
  # Production may instead connect directly as the role (LEDGER_DB_APP_ROLE=false
  # and a LOGIN role); grants are identical.
  module DatabaseRole
    ROLE = "galedra_app"
    PRIVILEGED_ENV = "LEDGER_DB_PRIVILEGED"

    GRANTS = [
      "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{ROLE}') THEN CREATE ROLE #{ROLE} NOLOGIN; END IF; END $$",
      "GRANT #{ROLE} TO CURRENT_USER",
      "GRANT USAGE ON SCHEMA public TO #{ROLE}",
      "GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public TO #{ROLE}",
      "GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO #{ROLE}",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO #{ROLE}",
      "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO #{ROLE}",
      "REVOKE UPDATE, DELETE, TRUNCATE ON contributions FROM #{ROLE}",
      "GRANT UPDATE (current_status) ON contributions TO #{ROLE}"
    ].freeze

    def self.enabled?
      ENV["LEDGER_DB_APP_ROLE"] != "false"
    end

    # True while migrations, schema loads, and other owner-level work run.
    def self.privileged_process?
      return true if ENV[PRIVILEGED_ENV].present?

      defined?(Rake) && Rake.respond_to?(:application) &&
        Rake.application.top_level_tasks.any? { |t| t.start_with?("db:") }
    end

    def self.switch?
      enabled? && !privileged_process?
    end

    # Runs the block with new connections made as the owner, then drops the
    # pool so later connections switch back to the role.
    def self.privileged_process
      previous = ENV[PRIVILEGED_ENV]
      ENV[PRIVILEGED_ENV] = "1"
      yield
    ensure
      previous.nil? ? ENV.delete(PRIVILEGED_ENV) : ENV[PRIVILEGED_ENV] = previous
      ActiveRecord::Base.connection_pool.disconnect!
    end

    # Temporarily resets the current connection to the owner role. Used by
    # tests that must tamper with the log and by owner-only operations.
    def self.as_owner
      ActiveRecord::Base.with_connection do |connection|
        connection.execute("RESET ROLE")
        begin
          yield
        ensure
          connection.execute("SET ROLE #{ROLE}") if switch?
        end
      end
    end

    # Creates the role and grants on every database of the current environment
    # (and test, when developing), connecting as the configured owner.
    def self.ensure_all!
      envs = [ Rails.env.to_s ]
      envs << "test" if Rails.env.development?
      envs.uniq.each do |env|
        ActiveRecord::Base.configurations.configs_for(env_name: env).each { |config| ensure!(config) }
      end
    end

    def self.ensure!(db_config)
      hash = db_config.configuration_hash
      connection = PG.connect(host: hash[:host], port: hash[:port], user: hash[:username],
                              password: hash[:password], dbname: hash[:database])
      GRANTS.each { |sql| connection.exec(sql) }
    rescue PG::ConnectionBad => e
      warn "ledger: skipping role setup for #{hash[:database]}: #{e.message.strip}"
    ensure
      connection&.close
    end
  end
end
