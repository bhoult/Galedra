# Galedra Hosting and Deployment Plan

## Status

This document defines the recommended hosting approach for the first public Galedra
node and the expected evolution path toward a federated network. It is written as an
implementation guide for Claude Code or another coding agent.

Revised 2026-09-19 against the code as built through Stage 25. Two things changed since
the first draft:

- **What runs today is not Kamal.** `compose.production.yaml` runs the production image
  with Thruster in front on any Linux box with Docker: Let's Encrypt for `TLS_DOMAIN`, or
  a Cloudflare tunnel with no open ports (README, "Serving it from home"). That is the
  supported path now and stays the fallback for a volunteer node. Kamal on a small cloud
  VM with managed PostgreSQL is the plan for the first *public* node; `config/deploy.yml`
  does not exist yet.
- **The stack is narrower than the draft assumed.** No pgvector, no object storage, no
  Redis: PostgreSQL 16 with `pg_trgm`, Solid Queue and Solid Cache in the Puma process,
  Active Storage on local disk and unused by the log. The spec (`11 §2`) fixes exactly
  two services, app and database, and every stage kept it.

The immediate goal is **simple, inexpensive, recoverable hosting**. Do not introduce
distributed-systems complexity during the first deployment.

---

# 1. Initial Hosting Decision

Use:

- **DigitalOcean** for the first public application node
- **Ubuntu 24.04 LTS**
- **Ruby 4.0 and Rails 8.1** (the pinned versions in `.ruby-version` and `Gemfile.lock`)
- **Kamal 2** for deployment
- **DigitalOcean Managed PostgreSQL 16** with the `pg_trgm` extension
- **Solid Queue and Solid Cache**, in the Puma process (`SOLID_QUEUE_IN_PUMA=true`)
- **Thruster** in front of Puma inside the container
- **Cloudflare R2** (or any S3-compatible bucket) for off-provider backups only
- **Cloudflare DNS**
- Docker as the deployment runtime

Initial production topology:

```text
                         Internet
                            |
                      Cloudflare DNS
                            |
                            v
                DigitalOcean Droplet
                     Ubuntu 24.04
                            |
                      Kamal Proxy
                            |
                    Thruster + Puma
                     Rails 8.1 app
                  (web and Solid Queue
                    in one process)
                            |
                            v
              DigitalOcean Managed
                 PostgreSQL 16 + pg_trgm
                            |
                     nightly backup
                            |
                            v
                     Cloudflare R2
```

The Rails application and PostgreSQL database should communicate over DigitalOcean
private networking where practical.

---

# 2. Why DigitalOcean First

The first deployment should optimize for:

1. developer attention;
2. predictable cost;
3. simple operations;
4. easy recovery;
5. portability;
6. compatibility with future federation.

DigitalOcean is preferred over raw AWS EC2 for the initial node because it exposes fewer
infrastructure concepts while still providing ordinary Linux VMs, private networking,
managed PostgreSQL, APIs, and automation-friendly tooling.

Do not depend on proprietary DigitalOcean services in the Galedra domain model. Nothing in
the code does today: the application is the same image whether it runs under
`compose.production.yaml` at home or under Kamal on a VM, and it must stay movable to
AWS, Hetzner, Linode/Akamai, bare metal, university infrastructure, or a home lab
without rewriting.

---

# 3. Initial Server Size

Start small:

```text
2 GB RAM
1-2 vCPU
Ubuntu 24.04 LTS
```

One process serves web and jobs. Jobs are light: score recomputation, snapshot creation,
summary generation, the hourly `SettleLoneVerdictsJob`, and source retrieval (Stage 17,
one fetch per host per minute, 2 MB cap). If memory pressure appears, scale the VM before
adding architectural complexity.

Do not prematurely provision Kubernetes, load balancers, multiple web nodes, Redis,
Sidekiq, a service mesh, or any orchestration beyond Kamal. Measure first.

---

# 4. Database

Use **DigitalOcean Managed PostgreSQL**.

Requirements:

- PostgreSQL 16 or newer;
- `pg_trgm` enabled (the schema enables it; near-duplicate claim search and affiliation
  deduplication use it). pgvector is **not** used: the spec defers semantic neighbours to
  P1 and nothing in the code needs it;
- automated provider backups/PITR enabled;
- private network access where available;
- SSL required;
- production credentials stored outside Git;
- database storage monitored.

Two things about the database are specific to Galedra:

- **It is the whole state.** The signed log (`contributions`), every projection, the
  server-custodied signing keys (encrypted with the Active Record Encryption keys), user
  accounts, tasks, and the tables outside the log (views, affiliations, reviews, counts)
  all live here. Sources hold no page text: a source is a link, a hash, and quoted
  excerpts, so there is no blob store to lose.
- **The app runs as a restricted role.** `Ledger::DatabaseRole` creates `galedra_app`
  (no `DELETE` or `TRUNCATE` on `contributions`, `UPDATE` only on `current_status`) and
  switches every runtime connection to it; migrations and `db:prepare` run as the owner.
  The connecting user therefore needs `CREATEROLE` and the right to grant on the schema.
  DigitalOcean's `doadmin` can do this. If a provider cannot, set
  `LEDGER_DB_APP_ROLE=false` and record the loss in the decision log: the append-only
  rule is then enforced by the application alone.

Losing the Rails VM should be recoverable in minutes. Losing accepted contributions, the
signed event history, provenance, audits, or graph state is not acceptable.

---

# 5. Deployment With Kamal

Use Kamal 2 as the deployment layer for the public node.

The intended workflow:

```text
git push
   |
tests pass
   |
bin/kamal deploy
   |
build image (--build-arg GALEDRA_REVISION=$(git describe --tags --always))
   |
push image
   |
deploy container
   |
health check GET /up
   |
route traffic to new release
```

The repository should gain a production-ready `config/deploy.yml`. Its container
command is the same one `compose.production.yaml` runs today:

```text
bin/rails db:prepare ledger:genesis ledger:release_models && exec ./bin/thrust ./bin/rails server
```

`ledger:genesis` appends seq 0 only when the log is empty and otherwise verifies that the
configured system key is the one registered there; a wrong key refuses to boot. The
`GALEDRA_REVISION` build argument is written to `REVISION` and shown on `/about` and in
`/api/v1/meta`, so a deployed node names its build.

The application should be deployable from the command line without manual web-console
actions after infrastructure setup. Useful operational commands are the Kamal
equivalents of `deploy`, `app logs`, `console`, and `shell`; exact syntax follows the
installed Kamal version.

Until `deploy.yml` exists, the supported production path is:

```bash
GALEDRA_REVISION=$(git describe --tags --always) docker compose -f compose.production.yaml up -d --build
```

with `TLS_DOMAIN`, `LEDGER_ALLOWED_HOSTS`, `LEDGER_NODE_URL`, `RAILS_MASTER_KEY`, and the
keys of section 11 in `.env`, or `--profile tunnel` with `CLOUDFLARE_TUNNEL_TOKEN` for a
node behind a router.

---

# 6. Container Registry

Use a standard OCI-compatible container registry.

Preferred choices:

1. GitHub Container Registry if convenient for the repository;
2. DigitalOcean Container Registry if operationally simpler;
3. another OCI-compatible registry if necessary.

Do not build a custom image-distribution mechanism. The image must remain
provider-neutral; `Dockerfile` already is.

---

# 7. DNS and TLS

Use Cloudflare for DNS.

```text
galedra domain
      |
Cloudflare DNS
      |
DigitalOcean public IP
      |
Kamal Proxy (Let's Encrypt)
      |
Thruster + Rails
```

TLS should be automated. Kamal Proxy with Let's Encrypt is acceptable for the initial
node; under compose, Thruster obtains the certificate itself for `TLS_DOMAIN`.

The application enforces `force_ssl` and `assume_ssl` in production and answers only the
hostnames in `LEDGER_ALLOWED_HOSTS` (plus `/up` for health checks). Set `LEDGER_NODE_URL`
to the public origin: keys, checkpoints, and `/api/v1/meta` name this node by it.

Cloudflare proxying may be enabled later for DDoS mitigation, request filtering, rate
limiting, and caching. Do not make Cloudflare-specific behaviour necessary for
application correctness. OAuth for connectors (Stage 16) needs the public origin to be
stable: hosted assistants complete OAuth against `https://<host>/mcp/connect`.

---

# 8. Object Storage

Not needed for the first public node.

Active Storage is configured (`local` disk under `storage/`, a volume under compose) and
nothing in the log uses it: sources are held by link, hash, and quoted excerpts (`01
§7`), and stored text, where a person pastes it, travels inside the signed payload and
lives in PostgreSQL (at most 1 MB). Share-card images are rendered on request.

Keep object storage for **backups** (section 9). If a later stage stores large
artifacts, Active Storage's S3 service points at R2 or any S3-compatible bucket with no
code change; the application must go on treating that store as replaceable, and source
hashes and durable identifiers stay in the log, never only in a bucket's metadata.

---

# 9. Backups

Provider-managed database backups are necessary but not sufficient. Maintain
**off-provider backups**.

Recommended nightly flow:

```text
Managed PostgreSQL
       |
       v
pg_dump --format=custom
       |
       v
Cloudflare R2 (or any S3-compatible bucket, another provider)
```

Also keep, off-provider and versioned:

- the secrets of section 11, above all `LEDGER_SYSTEM_PRIVATE_KEY` and the three
  `ACTIVE_RECORD_ENCRYPTION_*` keys: without the first, seq 0 no longer verifies and the
  node cannot sign; without the second, every server-custodied key is unreadable and
  every connected assistant and account must re-register;
- a periodic export of the signed log: `GET /api/v1/log?after_seq=&limit=` streams raw
  entries in seq order for mirroring, which is also how another node will replicate
  (Stage 23). Page through it to a file nightly;
- `/api/v1/meta` (chain head, current seq, released models, constitution hash, node
  identity) and the pinned snapshots with their signed checkpoints (`/api/v1/snapshots`).

A disaster-recovery test should prove that a fresh node can be reconstructed from:

```text
application source + secrets + database backup
```

and, independently, that the **log alone** suffices: restore only `contributions`, run
`bin/rails ledger:replay`, and compare the projection digests with the originals. That
second test is the one the design promises (`02 §1.1` rule 3) and the one federation
will depend on. Backups that have never been restored should not be considered proven.

---

# 10. Restore Procedure

Document and automate restoration.

```text
1.  Provision a fresh Ubuntu VM.
2.  Install Docker (and Kamal prerequisites, once Kamal is in use).
3.  Provision or restore PostgreSQL.
4.  Restore the latest trusted database backup.
5.  Put the secrets in place: the same system key, the same encryption keys.
6.  Deploy the current application image.
7.  Run migrations if needed (db:prepare does).
8.  bin/rails ledger:genesis     (verifies seq 0 against the configured key; appends nothing)
9.  bin/rails ledger:verify      (every hash and signature in the log)
10. bin/rails ledger:replay      (rebuild projections; digests must match the backup's)
11. Check GET /up and /api/v1/meta (current_seq and chain_head match the last export).
12. Restore DNS.
```

A future script or runbook should make this reproducible.

---

# 11. Secrets and Configuration

Never commit production secrets to Git. `.env.example` documents every variable; the
ones that matter for hosting:

| Variable | Role |
|---|---|
| `LEDGER_SYSTEM_PRIVATE_KEY`, `LEDGER_SYSTEM_PUBLIC_KEY` | The node's Ed25519 identity: signs every log entry, every checkpoint, genesis. Unrecoverable if lost; never regenerate on a live node. `bin/rails ledger:keygen` creates one. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `_DETERMINISTIC_KEY`, `_KEY_DERIVATION_SALT` | Encrypt server-custodied contributor keys. Unrecoverable if lost. `bin/rails db:encryption:init`. |
| `RAILS_MASTER_KEY` | Rails credentials. |
| `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME` | The managed database, over SSL and private networking. |
| `LEDGER_DB_APP_ROLE` | The restricted runtime role (`galedra_app`); `false` only where the provider forbids role creation. |
| `LEDGER_ALLOWED_HOSTS`, `LEDGER_NODE_URL`, `TLS_DOMAIN` | Hostnames answered, the public origin the node names itself by, the certificate domain. |
| `LEDGER_MODERATOR_KEY_IDS` | Moderator keys from the environment; admins can also flag accounts under Admin → Users. Published by `/api/v1/meta`. |
| `LEDGER_RETRIEVAL` | Stage 17 source fetches, `on` by default in production; `off` if the host must have no egress. |
| `LEDGER_DATA_LICENSE` | Defaults to `ODbL-1.0` (adopted 2026-09-19); published in `meta`. |
| `LEDGER_LLM_ADAPTER` | `stub` is the only adapter; the node runs no model. |
| `GALEDRA_REVISION` | Build argument, not a secret: the tag shown on `/about`. |
| `CLOUDFLARE_TUNNEL_TOKEN`, `LEDGER_CHATGPT_GPT_URL` | The tunnel profile; the published GPT linked from the connect page. |

Use Kamal-compatible secret management and environment injection. The signing key
deserves special handling: document its creation, storage, backup, rotation, revocation,
and recovery. Rotation is a log event (`REVOKE_KEY`, a new `REGISTER_KEY`), never a
silent swap of the environment variable, because seq 0 pins the first key.

**First run.** The first account to sign up is the admin (Stage 24). Sign up immediately
after the first deploy, before the address is shared, and appoint moderators from
Admin → Users or `LEDGER_MODERATOR_KEY_IDS`. `bin/rails admin:grant[email]` recovers a
site with no reachable admin.

---

# 12. Agent / LLM Infrastructure Access

The deployment should eventually be operable by Claude Code, Codex, or another trusted
engineering agent, through GitHub, Kamal, SSH, the DigitalOcean API, the Cloudflare API,
and PostgreSQL administrative tooling, each with least privilege.

An engineering agent may reasonably: read infrastructure state; inspect logs; deploy
releases; restart containers; run health checks and `ledger:verify`; run approved
migrations; create non-destructive infrastructure; update application DNS records; read
monitoring.

Initially, agents should **not**: delete the production database; delete all backups;
destroy the only production server; change account ownership; grant themselves broader
privileges; disable billing controls; remove audit history; rotate the system key or the
encryption keys; delete the DNS zone. Destructive actions require explicit human
approval.

---

# 13. Infrastructure as Code

Do not make Terraform or another IaC system a P0 requirement. The first deployment may
be provisioned manually or through provider CLI/API, but record every infrastructure
choice in the repository (this file and the decision logs under `implementation/`).
Once the deployment is stable, consider lightweight IaC so a fresh node can be
reproduced. The IaC layer must not become more complex than the infrastructure.

---

# 14. CI/CD

CI exists: `.github/workflows/ci.yml` runs `db:prepare` and the RSpec suite (with
`bin/brakeman`, `bin/bundler-audit`, and `bin/rubocop` available). Deployment stays
manual at first:

```text
local tests → git push → CI green → bin/kamal deploy (or docker compose ... up -d --build)
```

After stability, add a deployment workflow behind a human-approved step. Production
deployment should require successful tests. Note that `docker compose up` and Kamal both
run `db:prepare` on boot: a migration ships with its image, and a rollback that needs a
down migration is a manual act.

---

# 15. Monitoring

The first production node should expose basic operational signals:

- `GET /up` (200 when the app boots), used by Kamal and the container health check;
- `GET /api/v1/meta`: `current_seq` and `chain_head` should advance with use and match the
  nightly log export; `system_key_id` should never change;
- `bin/rails ledger:verify` on a schedule (nightly is enough), alerting on anything but a
  clean chain;
- Solid Queue: failed jobs, queue depth, and the recurring `SettleLoneVerdictsJob` and
  Solid Queue cleanup actually firing (`config/recurring.yml`);
- retrieval outcomes (Stage 17): a sudden run of `BLOCKED` or `TIMEOUT` usually means the
  host's egress or its reputation changed;
- Rails error logs (structured, tagged by request id), disk, memory, CPU;
- backup completion and the last successful restore test.

Do not build a large observability stack initially. Provider monitoring plus these
endpoints and structured logs are sufficient for P0/P1.

---

# 16. Security

At minimum:

- SSH keys only; disable password SSH login; non-root deployment user where practical;
- firewall only required ports (80, 443, SSH), or no inbound ports at all behind the
  Cloudflare tunnel;
- PostgreSQL not publicly exposed; SSL to it; the restricted runtime role (section 4);
- TLS everywhere externally; Rails production security defaults (`force_ssl`, host
  authorization, CSP meta tag);
- **egress**: the only outbound requests the node makes are Stage 17 source fetches,
  which resolve the host first and refuse private, loopback, link-local, and metadata
  addresses, follow at most five redirects with the same check, cap at 2 MB and 10 s, and
  respect robots.txt. Allow outbound 80/443 for them or set `LEDGER_RETRIEVAL=off`. The
  server never fetches an assistant-supplied URL on request (Invariant 11);
- rate limits already exist on every public write path (investigations, custodied
  writes, task leasing, sign-up of assistants, bug reports, affiliation requests) and
  daily caps per assistant token (200 anonymous, 1,000 named);
- signature validation before any contribution is accepted; automatic OS security
  updates or a documented patch routine.

Anonymous and agent write APIs are hostile input by design: notes, excerpts, headings,
reasons, and reports are never fed to scoring or to other agents' packets except as
marked untrusted text.

---

# 17. Expensive AI Work Must Stay Off the Central Server

Galedra runs no model, as a matter of principle (CLAUDE.md Invariant 18, amendment P-5),
not only of cost. The only adapter is the deterministic stub; summaries, claim
extraction, and affiliation deduplication run on it, and anything that needs a model is a
task or a tool for a connected assistant. The production server performs:

```text
issue compact research task
receive structured result
verify signature
validate schema
append contribution/event
update projections
schedule audit
recompute affected scores
settle reviews by consensus
fetch and hash a source held by reference (Stage 17)
serve API/UI/MCP
```

Expensive research runs on contributor machines, local GPUs, contributor-funded APIs,
independent research agents, and future federation nodes. This keeps central hosting
cost low and aligns with the volunteer-network design: the assistants connected over
MCP do the reading.

---

# 18. Portability Rule

No core Galedra object may depend on a provider-specific identity. This holds today:
primary keys are UUIDv7 or ids derived from the contribution that created the row
(`Ledger::Ids.derive`), every entry carries its content hash and chain hash, and Stage 23
added the node's own identity (`LEDGER_NODE_URL` plus the system key), a `home_url` on
every key, an explicit `visibility` on every entry, and a signed checkpoint on every
pinned snapshot. Human-facing URLs contain local routing identifiers; the epistemic
object underneath is portable between nodes.

---

# 19. Growth Path

## Stage 1 — First public node

```text
1 application VM (web + jobs)
1 managed PostgreSQL instance
1 backup bucket, off-provider
Cloudflare DNS
```

## Stage 2 — Moderate usage

Larger VM; larger PostgreSQL; a separate worker VM only if profiling justifies it
(`JOB_CONCURRENCY` and a second container running `bin/jobs` is the first step);
stronger monitoring; automated CI/CD; verified backups. Keep Rails monolithic.

## Stage 3 — First independent Galedra node

Treat this as a strategic milestone. Rather than buying a larger central database,
validate federation with what Stage 23 prepared:

- a second node mirrors the log through `GET /api/v1/log`, runs `ledger:replay`, and
  publishes matching projection digests;
- it verifies the origin's checkpoints under the origin's public key;
- keys registered there carry its `home_url`;
- read-only mirroring, verification, and recovery first; shard ownership experiments
  after; distributed multi-writer consensus never in this phase.

---

# 20. AWS Role

AWS remains a good future host. If a second independently operated node is created, AWS
is a strong candidate because provider diversity is desirable: DigitalOcean node,
AWS node, and a university or volunteer node behind a tunnel, federating. Lightsail
suits a simple node; EC2/RDS/S3 where the control is justified. The federation protocol
must not assume any one cloud provider.

---

# 21. Why Not Kubernetes

Do not introduce Kubernetes during the initial phases. It solves problems Galedra does
not yet have. Avoid EKS, DOKS, Helm, service meshes, and distributed orchestration.
Kamal (or compose) plus Docker on ordinary VMs remains sufficient until demonstrated
otherwise.

---

# 22. Claude Code Implementation Tasks

## Done

- production Docker image (`Dockerfile`, `GALEDRA_REVISION` build argument);
- a supported production path (`compose.production.yaml`: Thruster with Let's Encrypt,
  or a Cloudflare tunnel);
- `GET /up`; Solid Queue in production, in the Puma process; recurring jobs;
- `pg_trgm` enabled by the schema;
- every environment variable documented in `.env.example`;
- README deploy instructions ("Serving it from home");
- restricted runtime database role;
- the node's identity, keys' home URL, entry visibility, signed checkpoints, and the
  log export for mirroring (Stage 23);
- no provider credentials in Git; globally durable object ids.

## To do for the first public node

- `config/deploy.yml` for Kamal, with the compose command as the container command and
  `/up` as the health check;
- `bin/backup` (`pg_dump` to an S3-compatible bucket, plus the log export and `meta`);
- `bin/restore-check` (restore into a scratch database, `ledger:verify`, `ledger:replay`,
  compare digests) and a written runbook for section 10;
- `bin/verify-production` (`/up`, `meta` against the last export, `ledger:verify`);
- a scheduled `ledger:verify`;
- Active Storage S3 configuration, only if a later stage stores artifacts.

Scripts must be safe by default. A restore script must never overwrite production data
without explicit confirmation.

---

# 23. Claude Must Not Do Without Explicit Approval

Do not automatically: purchase cloud services; provision paid infrastructure; change DNS
for an existing production domain; destroy infrastructure; delete databases or backups;
rotate the system key or the encryption keys; expose PostgreSQL publicly; introduce
Kubernetes; migrate the application away from Rails; add Redis or pgvector without
measured need. Infrastructure preparation in the repository is acceptable. Irreversible
account-level actions require explicit authorization.

---

# 24. Deployment Acceptance Criteria

The first public deployment is successful when:

1. a clean Ubuntu host runs Galedra through Kamal (or compose) from the repository alone;
2. HTTPS works at the public name, and `/api/v1/meta` reports that name as `node.url`;
3. Rails connects to managed PostgreSQL over SSL as the restricted role;
4. `pg_trgm` works (near-duplicate search on `/claims` and `search_claims`);
5. Solid Queue processes jobs, and the hourly recurring job fires;
6. the first sign-up became the admin, and a moderator is appointed;
7. a signed contribution is accepted through a connected assistant over OAuth;
8. `bin/demo` is **not** run against production (it refuses a non-empty log anyway); the
   scoring goldens pass in CI;
9. application restart loses no state; `ledger:genesis` verifies the pinned key;
10. a nightly off-provider backup and log export succeed;
11. a backup restores into a test environment, `ledger:verify` is clean, and
    `ledger:replay` reproduces the projection digests;
12. production secrets are absent from Git;
13. the node can be recreated without relying on undocumented console settings.

---

# 25. Guiding Principle

The first Galedra host should be deliberately ordinary:

> **a small Linux server, managed PostgreSQL, Docker, and Kamal or compose.**

The project should spend complexity on the epistemic model, not cloud infrastructure.
The infrastructure is successful when it is boring, inexpensive, recoverable, portable,
agent-operable, and easy to replace. The long-term goal is not one enormous Galedra
server; it is a node that others can run themselves, and Stage 23 made the log something
another node can verify and continue.
