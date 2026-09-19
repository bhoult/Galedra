# frozen_string_literal: true

module Governance
  # What is running: the git revision (a REVISION file written at image build,
  # else git itself in development, else GALEDRA_REVISION), the repository,
  # and the platform versions. Shown on /about and in /api/v1/meta so a mirror
  # or a bug report can say exactly which build it saw.
  module Software
    NAME = "galedra"
    REPOSITORY = "https://github.com/bhoult/Galedra"
    REPOSITORY_PUBLIC = ENV.fetch("GALEDRA_REPOSITORY_PUBLIC", "true") == "true"
    MAINTAINER = {
      name: "Brandon Hoult",
      email: "bhoult@gmail.com",
      linkedin: "https://www.linkedin.com/in/brandon-hoult-02b188b/",
      github: "https://github.com/bhoult",
      paypal: "https://paypal.me/bhoult",
      cashapp: "https://cash.app/$bhoult",
      cashtag: "$bhoult"
    }.freeze
    REVISION_FILE = Rails.root.join("REVISION")
    REVISION_ENV = "GALEDRA_REVISION"

    module_function

    def revision
      @revision ||= from_file || from_git || ENV[REVISION_ENV].presence || "unknown"
    end

    def from_file
      File.read(REVISION_FILE).strip.presence if File.exist?(REVISION_FILE)
    end

    def from_git
      return nil unless File.directory?(Rails.root.join(".git"))

      # The checkout may be a bind mount owned by another user (docker compose).
      out = IO.popen([ "git", "-c", "safe.directory=*", "-C", Rails.root.to_s, "describe", "--tags", "--always", "--dirty" ], err: File::NULL, &:read)
      out.to_s.strip.presence
    rescue SystemCallError
      nil
    end

    def repository_public? = REPOSITORY_PUBLIC

    def to_h
      { name: NAME, revision: revision, repository: REPOSITORY, ruby: RUBY_VERSION, rails: Rails.version }
    end
  end
end
