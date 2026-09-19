# Stage 0 — Skeleton

**Status:** implemented · tag `stage-00-skeleton` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-00-skeleton` · **Spec:** 07 Phase 0, 11 §2, §5, §10, 10 "Required Artifacts"

Goal: a Rails 8 application that boots under Docker Compose, has CI, and serves the
constitution hash. No domain logic.

Deliverables:

- Toolchain: `asdf plugin update ruby`, install the latest stable Ruby (4.0.7 at planning
  time), `gem install rails` at the latest stable (8.1.3.1 at planning time). Pin Ruby in
  `.tool-versions` and `.ruby-version`; pin Rails in the Gemfile to the exact installed
  patch line (e.g. `~> 8.1.3`).
- Rails app generated at the repo root (`--database=postgresql`, `--skip-jbuilder`, no JS
  bundler; importmap + Hotwire only). The Docker image uses the same Ruby version.
- `docker-compose.yml` with exactly two services, `app` and `db` (PostgreSQL 16). The app
  container runs web + `bin/jobs` via `Procfile.dev` or a second process in the same
  service. Installs the missing compose plugin; the Decision Log records how.
- Solid Queue, Solid Cache, Active Storage (local disk) configured against the same
  Postgres database.
- Rails 8 authentication generator run (`users`, `sessions`), with a minimal Hotwire
  layout and a home page that renders.
- RSpec (`rspec-rails`), FactoryBot, and a system-test driver. Record the choice.
- GitHub Actions CI: lint (RuboCop, rails-omakase config), `bundle exec rspec` against a
  Postgres service, `bin/brakeman`.
- `.env.example` documenting every environment variable, including
  `LEDGER_SYSTEM_PRIVATE_KEY` and `LEDGER_SYSTEM_PUBLIC_KEY` placeholders (used from
  Stage 1).
- `CONSTITUTION.md` at the repo root: a byte-identical copy of `12-constitution.md`, with
  a test asserting the two files match.
- `Governance::Constitution` service returning `{version, hash}` where the hash is
  `sha256:` + hex over the file bytes.
- `GET /api/v1/meta` returning `constitution_version` and `constitution_hash` (other
  fields are added in later stages).
- This file's Decision Log started: Ruby, Rails, Postgres, gem versions; RSpec choice;
  UUIDv7 approach chosen (Postgres 16 has no native `uuidv7()`; pick a SQL function or a
  gem and document).

Acceptance:

1. `docker compose up` serves the home page.
2. `bundle exec rspec` passes locally and in CI.
3. `/api/v1/meta` returns a constitution hash that equals `sha256sum CONSTITUTION.md`.

## Decision Log (2026-09-17)

- Versions: Ruby 4.0.7 (asdf, YJIT off: no rustc on the build machine), Rails 8.1.3.1,
  Bundler 4.0.20, Node 24.21.0 (asdf, current LTS; 26.x is not LTS until October 2026),
  PostgreSQL 16 (`postgres:16` image), pg 1.6, Solid Queue 1.7.0, RSpec via rspec-rails.
  Rails pinned `~> 8.1.3, >= 8.1.3.1`.
- `rails new` was run with `--skip-bundle`, which also skipped the after-bundle installers.
  importmap, Turbo, Stimulus, Solid Cache, Solid Queue, and Solid Cable were installed
  afterwards with their own generators.
- Test framework: RSpec, FactoryBot, Capybara, selenium-webdriver. Minitest skipped at
  generation. A system-test driver is present but no system tests run before Stage 10.
- Single database. The Solid installers' `db/*_schema.rb` files were folded into one
  migration (`create_solid_tables`) and deleted, and the production multi-database
  `connects_to` wiring removed, so development, test, and production each use one
  PostgreSQL database as 11 §2 requires. Solid Queue runs inside Puma via the
  `solid_queue` Puma plugin (`SOLID_QUEUE_IN_PUMA=true`) rather than a second process,
  so the `app` service is one container and one process tree.
- Database connection settings come from `DB_HOST`, `DB_PORT`, `DB_USERNAME`,
  `DB_PASSWORD` (documented in `.env.example`, loaded by dotenv locally and by Compose).
  CI sets the same variables against a Postgres 16 service.
- Docker Compose plugin was missing and sudo is unavailable to the agent; Compose v5.5.1
  was installed as a user-level CLI plugin in `~/.docker/cli-plugins/`. `Dockerfile.dev`
  is the development image; the generated `Dockerfile` remains the production image.
- `CONSTITUTION.md` is a byte-identical copy of `12-constitution.md`, asserted by a spec.
  `Governance::Constitution` parses the version from the file's header table and hashes
  the raw bytes. `GET /api/v1/meta` returns `constitution_version` and
  `constitution_hash`. API controllers inherit `Api::V1::BaseController`
  (`ActionController::API`), outside the session-based `Authentication` concern that the
  Rails 8 generator adds to `ApplicationController`.
- Rails 8 authentication generator was run (`users`, `sessions`, password reset). The
  home page is public via `allow_unauthenticated_access`.
- UUIDv7 primary keys are deferred to Stage 1, where the first ledger table is created.
- Deviation: `07` Phase 0 names `IMPLEMENTATION.md` as a deliverable; it already existed
  as the plan. `10` names `test/fixtures/`; RSpec uses `spec/fixtures/` (Stage 1).
- CI workflow triggers on `master` (the repo's branch), not the generated `main`.
- Acceptance: `docker compose up` serves the home page on port 3000; `bundle exec rspec`
  passes; `/api/v1/meta` hash equals `sha256sum CONSTITUTION.md`.
