# Galedra Hosting and Deployment Plan

## Status

This document defines the recommended hosting approach for the first public Galedra node and the expected evolution path toward a federated network.

It is written as an implementation guide for Claude Code or another coding agent.

The immediate goal is **simple, inexpensive, recoverable hosting**.

Do not introduce distributed-systems complexity during the first deployment.

---

# 1. Initial Hosting Decision

Use:

- **DigitalOcean** for the first public application node
- **Ubuntu 24.04 LTS**
- **Rails 8**
- **Kamal 2** for deployment
- **DigitalOcean Managed PostgreSQL**
- **pgvector**
- **Solid Queue**
- **Active Storage**
- **Cloudflare R2** for off-provider backups and object storage
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
                         Rails 8
                      /           \
               Web process     Solid Queue
                      \           /
                            |
                            v
              DigitalOcean Managed
                    PostgreSQL
                    + pgvector

                            |
                     backup/export
                            |
                            v
                     Cloudflare R2
```

The Rails application and PostgreSQL database should communicate over DigitalOcean private networking where practical.

---

# 2. Why DigitalOcean First

The first deployment should optimize for:

1. developer attention;
2. predictable cost;
3. simple operations;
4. easy recovery;
5. portability;
6. compatibility with future federation.

DigitalOcean is preferred over raw AWS EC2 for the initial node because it exposes fewer infrastructure concepts while still providing ordinary Linux VMs, private networking, managed PostgreSQL, APIs, and automation-friendly tooling.

Do not depend on proprietary DigitalOcean services in the Galedra domain model.

The application should remain movable to AWS, Hetzner, Linode/Akamai, bare metal, university infrastructure, home lab, or another provider without rewriting the application.

---

# 3. Initial Server Size

Start small:

```text
2 GB RAM
1-2 vCPU
Ubuntu 24.04 LTS
```

If production memory pressure becomes significant, scale the application VM before adding architectural complexity.

Do not prematurely provision:

- Kubernetes;
- load balancers;
- multiple web nodes;
- Redis;
- dedicated Sidekiq infrastructure;
- service mesh;
- container orchestration beyond Kamal.

Measure first.

---

# 4. Database

Use **DigitalOcean Managed PostgreSQL**.

Requirements:

- PostgreSQL 16 or newer;
- pgvector enabled;
- automated provider backups/PITR enabled;
- private network access where available;
- SSL required;
- production credentials stored outside Git;
- database storage monitored.

The database is the most important centralized asset during the pre-federation phase.

Losing the Rails VM should be recoverable. Losing accepted contributions, signed event history, provenance, audits, or graph state is not acceptable.

---

# 5. Deployment With Kamal

Use Kamal 2 as the deployment layer.

The intended workflow:

```text
git push
   |
tests pass
   |
bin/kamal deploy
   |
build image
   |
push image
   |
deploy container
   |
health check
   |
route traffic to new release
```

The repository should contain a production-ready:

```text
config/deploy.yml
```

The application should be deployable from the command line without requiring manual web-console actions after infrastructure setup.

Useful operational commands should include the Kamal equivalents of:

```bash
bin/kamal deploy
bin/kamal app logs
bin/kamal console
bin/kamal shell
```

Exact command syntax should follow the installed Kamal version.

---

# 6. Container Registry

Use a standard OCI-compatible container registry.

Preferred choices:

1. GitHub Container Registry if convenient for the repository;
2. DigitalOcean Container Registry if operationally simpler;
3. another OCI-compatible registry if necessary.

Do not build a custom image-distribution mechanism.

The application Docker image must remain provider-neutral.

---

# 7. DNS and TLS

Use Cloudflare for DNS.

Initial topology:

```text
galedra domain
      |
Cloudflare DNS
      |
DigitalOcean public IP
      |
Kamal Proxy
      |
Rails
```

TLS should be automated.

Kamal Proxy / Let's Encrypt is acceptable for the initial node.

Cloudflare proxying may be enabled later for DDoS mitigation, request filtering, rate limiting, caching, and abuse protection.

Do not make Cloudflare-specific behavior necessary for application correctness.

---

# 8. Object Storage

Use Active Storage.

Development:

```text
local filesystem
```

Production:

```text
Cloudflare R2
```

or another S3-compatible object store.

Store large source artifacts outside PostgreSQL when appropriate.

The application should treat object storage as replaceable.

Do not store critical provenance solely in opaque storage-provider metadata. Source hashes and durable identifiers belong in PostgreSQL/event records.

---

# 9. Backups

Provider-managed database backups are necessary but not sufficient.

Maintain **off-provider backups**.

Recommended nightly flow:

```text
Managed PostgreSQL
       |
       v
pg_dump / logical export
       |
       v
compression
       |
       v
Cloudflare R2
```

Also periodically export:

- signed contribution/event log;
- graph snapshot metadata;
- scoring-model versions;
- schema versions;
- checkpoint hashes;
- federation-readiness metadata.

A successful disaster-recovery test should eventually prove that a fresh node can be reconstructed from:

```text
application source
+
database backup
+
object storage
+
signed event history
```

Backups that have never been restored should not be considered proven.

---

# 10. Restore Procedure

Document and automate restoration.

Expected recovery outline:

```text
1. Provision fresh Ubuntu VM.
2. Install Docker/Kamal prerequisites.
3. Provision or restore PostgreSQL.
4. Restore latest trusted database backup.
5. Restore object storage configuration.
6. Configure production secrets.
7. Deploy current application image.
8. Run migrations if needed.
9. Verify contribution-chain integrity.
10. Verify graph projections.
11. Verify health checks.
12. Restore DNS.
```

A future script or runbook should make this reproducible.

---

# 11. Secrets

Never commit production secrets to Git.

Secrets may include:

- Rails master key;
- database credentials;
- container-registry credentials;
- Cloudflare credentials;
- R2 credentials;
- DigitalOcean API token;
- signing keys;
- SMTP/API credentials;
- external model/API keys.

Use Kamal-compatible secret management and environment injection.

The canonical signing identity for the node deserves special handling.

Do not casually regenerate production signing keys during redeployment.

Document key creation, storage, backup, rotation, revocation, and recovery.

---

# 12. Agent / LLM Infrastructure Access

The deployment should eventually be operable by Claude Code, Codex, or another trusted engineering agent.

Possible control surfaces:

```text
GitHub
Kamal
SSH
DigitalOcean API / doctl / MCP
Cloudflare API
PostgreSQL administrative tooling
```

Agent credentials should use least privilege.

An engineering agent may reasonably be allowed to:

- read infrastructure state;
- inspect logs;
- deploy application releases;
- restart application containers;
- run health checks;
- run approved migrations;
- create non-destructive infrastructure;
- update application DNS records;
- read monitoring state.

Initially, agents should **not** be permitted to:

- delete the production database;
- delete all backups;
- destroy the only production server;
- change account ownership;
- grant themselves broader privileges;
- disable billing controls;
- remove audit history;
- rotate root credentials without approval;
- delete the DNS zone.

Destructive actions should require explicit human approval.

---

# 13. Infrastructure as Code

Do not make Terraform or another IaC system a P0 requirement.

The first deployment may be provisioned manually or through provider CLI/API.

However, record all infrastructure choices in the repository.

Once the deployment is stable, consider adding lightweight Infrastructure as Code so a fresh node can be reproduced.

The IaC layer must not become more complex than the infrastructure itself.

---

# 14. CI/CD

Initial deployment may be manual:

```text
local tests
git push
bin/kamal deploy
```

After stability, move toward:

```text
Pull Request
    |
    v
GitHub Actions
    |
    +-- tests
    +-- lint
    +-- security checks
    |
merge main
    |
    v
deployment workflow
    |
    v
Kamal deploy
```

Production deployment should require successful tests.

Prefer a human-approved deploy step initially.

---

# 15. Monitoring

The first production node should expose basic operational signals:

- HTTP health endpoint;
- Rails error logs;
- worker health;
- database connectivity;
- disk usage;
- memory usage;
- CPU usage;
- queue depth;
- failed jobs;
- backup completion;
- last successful graph replay/check;
- contribution-signature verification failures.

Do not build a large observability stack initially.

Provider monitoring plus application-level health endpoints and structured logs are sufficient for P0/P1.

---

# 16. Security

At minimum:

- SSH keys only;
- disable password SSH login;
- non-root deployment user where practical;
- firewall only required ports;
- PostgreSQL not publicly exposed unless strictly necessary;
- TLS everywhere externally;
- Rails production security defaults;
- rate limits on public write endpoints;
- signature validation before contribution acceptance;
- separate credentials for application and administrative DB access;
- automatic OS security updates or documented patch routine.

Future anonymous/agent write APIs must be treated as hostile input.

---

# 17. Expensive AI Work Must Stay Off the Central Server

Do not host large-model inference on the production node.

The production Galedra server should mainly perform:

```text
issue compact research task
receive structured result
verify signature
validate schema
append contribution/event
update projections
schedule audit
recompute affected scores
serve API/UI
```

Expensive research should run on:

- contributor machines;
- local GPUs;
- contributor-funded APIs;
- independent research agents;
- future federation nodes.

This keeps central hosting cost low and aligns with the future volunteer-network design.

---

# 18. Portability Rule

No core Galedra object may depend on a DigitalOcean-specific identity.

Bad:

```text
claim_id = database row 12345
```

Preferred:

```text
claim_id = globally durable UUID/ULID
content_hash = sha256:...
origin_contribution_id = globally durable identifier
```

Human-facing URLs may contain local routing identifiers, but the underlying epistemic object must remain portable between nodes.

---

# 19. Growth Path

## Stage 1 — First public node

```text
1 application VM
1 managed PostgreSQL instance
1 object-storage bucket
Cloudflare DNS
```

Expected scale:

- initial users;
- early public experiments;
- small research corpus;
- low operational cost.

## Stage 2 — Moderate usage

Possible changes:

- larger application VM;
- larger PostgreSQL instance;
- separate worker VM if profiling justifies it;
- stronger monitoring;
- automated CI/CD;
- better backup verification.

Keep Rails monolithic unless profiling identifies a real bottleneck.

## Stage 3 — First independent Galedra node

Treat this as a strategic milestone.

Instead of solving every storage or scaling problem by buying a larger central database, begin validating federation.

Example:

```text
             Original node
               /       \
              /         \
         University    Volunteer
            node         node
```

The first federation experiment should prioritize:

- signed snapshot replication;
- read-only mirroring;
- verification;
- recovery;
- shard ownership experiments.

Do not begin with distributed multi-writer consensus.

---

# 20. AWS Role

AWS remains a good future host.

If a second independently operated node is created, AWS is a strong candidate because provider diversity is desirable.

Potential future topology:

```text
DigitalOcean node
        |
        | federation
        |
AWS node
        |
        | federation
        |
university / volunteer node
```

Provider diversity is preferable to deploying all federation nodes inside one cloud.

AWS Lightsail may be used for a simple node. EC2/RDS/S3 can be used where the additional control is justified.

The federation protocol must not assume any one cloud provider.

---

# 21. Why Not Kubernetes

Do not introduce Kubernetes during the initial phases.

Kubernetes solves problems Galedra does not yet have.

Avoid:

- EKS;
- DOKS;
- Helm;
- service mesh;
- distributed orchestration.

Kamal + Docker + ordinary VMs should remain sufficient until demonstrated otherwise.

---

# 22. Claude Code Implementation Tasks

Claude should implement or prepare the following.

## P0 Deployment Readiness

- production Docker image builds successfully;
- Rails production configuration documented;
- `config/deploy.yml` created for Kamal;
- production health endpoint exists;
- Solid Queue runs correctly in production;
- pgvector extension is enabled by migration/setup;
- Active Storage production configuration supports S3-compatible storage;
- environment variables/secrets are documented;
- README contains deploy instructions;
- backup script or documented backup command exists;
- restore runbook exists;
- no provider credentials are committed;
- production uses globally durable object IDs.

## Optional automation

Claude may additionally create:

```text
bin/backup
bin/restore-check
bin/verify-production
```

or equivalent tasks.

Scripts must be safe by default.

A restore script must never overwrite production data without explicit confirmation.

---

# 23. Claude Must Not Do Without Explicit Approval

Do not automatically:

- purchase cloud services;
- provision paid infrastructure;
- change DNS for an existing production domain;
- destroy infrastructure;
- delete databases;
- delete backups;
- rotate production signing keys;
- expose PostgreSQL publicly;
- introduce Kubernetes;
- migrate the application away from Rails;
- add Redis without measured need.

Infrastructure preparation in the repository is acceptable.

Actual irreversible account-level actions require explicit authorization.

---

# 24. Deployment Acceptance Criteria

The first public deployment is successful when:

1. a clean Ubuntu host can run Galedra through Kamal;
2. HTTPS works;
3. Rails connects to managed PostgreSQL;
4. pgvector works;
5. Solid Queue processes background jobs;
6. object uploads work;
7. a signed contribution can be accepted;
8. deterministic scoring works;
9. application restart does not lose state;
10. nightly off-provider backup succeeds;
11. a backup can be restored into a test environment;
12. production secrets are absent from Git;
13. the node can be recreated without relying on undocumented console settings.

---

# 25. Guiding Principle

The first Galedra host should be deliberately ordinary.

Use:

> **a small Linux server, managed PostgreSQL, object storage, Docker, and Kamal.**

The project should spend complexity on the epistemic model, not cloud infrastructure.

The infrastructure is successful when it is:

- boring;
- inexpensive;
- recoverable;
- portable;
- agent-operable;
- and easy to replace.

The long-term goal is not to build one enormous Galedra server.

It is to prove a node that others can eventually run themselves.
