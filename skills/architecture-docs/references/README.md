# Reference rubrics — what to load when

`templates.md` and `approaches.md` load always (step 1 of the skill). Every other rubric loads
on demand, when the row's trigger enters the scope of the document you are authoring or the
question you are answering. All share one shape: a driver table, options with use when / pros /
cons / typical mistakes, and a "Recording the choice" close. Files whose facts go stale
(licenses, product versions) carry a `written_against` stamp — trust the stamp's date, not the
file's presence.

| Rubric | Load when |
|---|---|
| `deployment.md` | hosting, build/release path, schema-migration-on-deploy or configuration is being decided; authoring `06-deployment.md` |
| `containers.md` | the repo deploys (or may deploy) in containers — compose depth, Kubernetes building blocks, the compose→K8s bridge |
| `delivery-pipeline.md` | CI/CD tooling, the environment set (dev/staging/prod/previews) or the promotion path to production is being decided — or releases are done by hand today and the team wants them reproducible |
| `iac-and-drift.md` | the design touches environments, DR, deployment topology, or anything provisioned outside the application repo — whether it is declared in code, where state lives, and how drift is detected |
| `release-strategy.md` | a deployment/release strategy is being chosen, DB schema migrations are being planned, health checks and rollout automation are being wired, or where migrations execute in the pipeline is undecided |
| `feature-flags.md` | release strategy, progressive delivery, dark launches or kill switches are in scope — or a rollback plan mentions reverting migrations |
| `edge-proxy.md` | anything is exposed to the public internet, a proxy/ingress/load-balancer choice is open, the TLS termination point is undecided, or an app server (Kestrel, uvicorn, node) is about to be published directly |
| `tls-certificates.md` | anything serves HTTPS, a certificate is being requested or renewed, mTLS/internal PKI comes up, or someone proposes buying a cert and setting a calendar reminder — who issues, rotates and revokes |
| `dns-and-domains.md` | domain registration, DNS host choice, environment subdomains, TTLs, CAA records, apex/www handling or DNS-driven failover is in scope — and who owns the domain |
| `abuse-protection.md` | any internet-facing endpoint, a self-run login/token endpoint, a per-call-cost backend (LLM, SMS, email) or a multi-tenant API — rate limits per client/tenant/IP, bot handling, request size caps, brute-force lockout |
| `frontend-delivery.md` | the system has a browser UI and its rendering strategy, asset hosting, caching or proxy wiring is being decided — static SPA, SSR, server-rendered pages or hybrid |
| `machine-topology.md` | host count, a second host or a load balancer, VM sizing or database HA is in scope — or "we need high availability" is said with no number attached |
| `disaster-recovery.md` | a region-wide outage is unacceptable, compliance demands a DR plan, or someone says "multi-region" — before money is spent on standby infrastructure |
| `global-audience.md` | the profile records user geography, or the design mentions global users, multi-region, CDN, edge, data residency or worldwide latency |
| `finops-guardrails.md` | any managed cloud service, SaaS observability, LLM API or OLAP engine enters the design; or budget is tight; or nobody can name the top three cost drivers |
| `operations.md` | secrets storage, telemetry backends, alerting/SLOs, health probes or backup/restore are in scope |
| `slo-error-budgets.md` | availability targets, alerting strategy or on-call scope are being decided, or someone proposes "five nines" or a wall of threshold alerts |
| `incident-response.md` | availability is high, an SLO exists, backups exist, or the system has real users whose outage anyone would notice — who is paged, the severities, and the runbooks |
| `observability-conventions.md` | an observability backend is chosen and services are about to be instrumented, or cross-service debugging already hurts — log schema, metric names, cardinality, sampling, dashboards |
| `frontend-observability.md` | the frontend is a real SPA/SSR app serving external or business-critical users — error tracking, RUM/web vitals, session replay, browser-to-backend trace correlation |
| `production-access.md` | operators reach production through an admin UI, SSH or a database console — how that access is authenticated, scoped, audited and revoked; always relevant once the system is in production |
| `logging-and-audit.md` | log design (structure, levels, PII, retention) or an audit trail is in scope |
| `correlation.md` | one user action crosses several components and must be followable through every component's logs |
| `security.md` | any trust boundary is in scope — threat model, IdP choice, session/token shape, tenant isolation, authz model, S2S pattern |
| `threat-modeling.md` | any new externally reachable surface — webhook, admin endpoint, file upload, third-party callback, LLM feature, new data class — or the words "security review" appear |
| `session-model.md` | the system has any browser-facing authenticated UI: server-side session cookie, BFF or tokens in the browser, and how logout, revocation and CSRF work — decide before the first login handler |
| `tenant-operations.md` | the system is multi-tenant SaaS and quotas, noisy neighbours, per-tenant backup/restore/export, tenant migration or usage billing come up — the isolation model itself lives in `security.md` |
| `regulated-data.md` | the system touches payment cards (PCI-DSS) or US health data (HIPAA), or a client contract requires either — load before choosing a payment integration, cloud services or a logging pipeline |
| `supply-chain-security.md` | dependencies, base images, CI artifacts, registries, EU CRA exposure, or "how do we know what we ship" comes up |
| `egress-control.md` | outbound webhooks or partner APIs allowlist your source IPs, autoscaling makes node IPs ephemeral, compliance treats egress as an exfiltration channel, or high-volume traffic may transit a NAT gateway |
| `auth-flows.md` | after `security.md`'s decisions: the concrete grant per client type (web, SPA, CLI, service), token exchange, and whether Keycloak/the chosen IdP actually supports it |
| `gateway-bff.md` | the session answer is a BFF — how many, whether a routing gateway tier belongs in front, and how each BFF exchanges the session for per-downstream tokens |
| `mtls-pki.md` | the S2S answer is mTLS — who issues, rotates, distributes and revokes the certificates |
| `communication.md` | a `Talks to` edge needs its protocol and contract; API versioning and deprecation policy |
| `message-bus.md` | `communication.md`'s class decision points at a broker — which product, and what running it costs |
| `resilience-patterns.md` | any synchronous outbound dependency or at-least-once message consumer exists — the timeout, retry, breaker, bulkhead and idempotency policy per edge; always for microservices or events |
| `api-governance.md` | a contract another team or an external party consumes is being designed or changed — versioning scheme, deprecation policy, event-schema compatibility, the CI diff gate |
| `api-consumers.md` | the profile records external API consumers, or the design mentions partners, third-party integrations, a public API, a developer portal, API keys, or webhooks for external parties |
| `webhooks-out.md` | communication includes webhooks, or the system emits events external customers consume at their own URLs — signing, retry window, per-endpoint DLQ, the endpoint-management UI |
| `background-jobs.md` | anything runs later or on a schedule — nightly cleanup, reports, retries, delayed notifications — or a timer/`BackgroundService` exists and replicas are planned |
| `email-notifications.md` | the system sends any email — password resets, invites, receipts, digests — or a signup/checkout flow is about to call SMTP inline; or deliverability, bounces and DMARC come up |
| `realtime-channel.md` | the UI needs live updates — notifications, dashboards, chat, progress, LLM token streams — and the transport and its scale-out story are being chosen |
| `payments-integration.md` | the system charges customers, holds a ledger or handles subscriptions — integration depth against PCI scope, the PSP, and the idempotency/webhook/ledger mechanics |
| `testing.md` | the test strategy (distribution shape, kinds, environments) is being decided |
| `load-and-failure-testing.md` | the design claims a capacity number, an autoscaling behaviour, an HA failover or a retry/timeout policy that nobody has watched work — especially before a launch or campaign |
| `accessibility.md` | the frontend is public-facing, the product serves EU consumers (European Accessibility Act scope), or a frontend architecture/component library is being chosen where a11y capability is a selection criterion |
| `licensing.md` | a dependency or platform choice hangs on what its license permits |
| `internal-structure.md` | how the code inside one unit is organised — layers vs ports vs slices — or a task cut needs the unit's internal seams |
| `design-patterns.md` | proposing or reviewing component-level seams — which pattern, and whether its force is recorded |
| `ddd.md` | the domain's rules are the hard part — language, bounded contexts, aggregates, and TDD as design pressure |
| `diagrams.md` | choosing a diagram type — what each UML/C4 view describes, mermaid vs LikeC4 authoring |
| `data.md` | a second store (cache, search index, replica, OLAP) is on the table, or staleness/sync questions are in scope |
| `caching-strategy.md` | caching, Redis/Valkey, a CDN, `Cache-Control`, TTLs, "the DB is slow", or a read-heavy endpoint under spiky load is in scope — which layer earns its keep, and in what order |
| `database-products.md` | the primary datastore product is being chosen or reviewed — self-hosted vs managed, a licence question about a database, or which HA and failover mechanism a given engine actually implies |
| `database-operations.md` | a relational primary store has moved past schema into deployment — connection pooling, autovacuum and bloat, slow-query review, or a major version with an EOL date approaching |
| `database-tls-operations.md` | TLS on the datastore is in scope — who issues its certificates, whether the engine reloads them without a restart, cloud CA bundles and forced rotations, `sslmode`/verification, or mTLS to the database |
| `blob-storage.md` | the system accepts user uploads or generates files that must survive a redeploy — where the bytes live, how they get in, how they are served back |
| `search-products.md` | a search decision goes beyond DB full-text, or relevance/typo-tolerance/faceting outgrows `LIKE` and `tsvector` — which engine, and how the index stays in sync |
| `data-lifecycle-privacy.md` | the system stores personal data, compliance includes GDPR/residency/audit, a cache/index/OLAP/log pipeline receiving user data is being added, or an erasure request could arrive |
| `i18n-locale.md` | users in more than one country or timezone, user-facing dates or money, translatable content, or a stated plan to expand — decide before the schema is frozen |
| `llm-features.md` | the system embeds an LLM/AI feature — interaction shape, provider coupling, prompts as contracts, guardrails, evals |
| `stacks/dotnet.md` · `stacks/react.md` · `stacks/python.md` | the product repo runs that stack — project-type choices and their consequences; load the matching one only |
