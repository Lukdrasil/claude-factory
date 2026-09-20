# Delivery pipeline — environments, one artifact, and the path to production

Load this when CI/CD tooling is being chosen, the environment set (dev, staging, prod, previews)
is being defined, someone is deciding how a build reaches production, or releases are currently
done by hand and the team wants them reproducible. `deployment.md` decides what executes the
process and where it runs; this file settles what builds the artifact, which environments exist,
and how the artifact is promoted between them. `release-strategy.md` takes over at the moment the
new version replaces the old one, and `iac-and-drift.md` owns the infrastructure those
environments are made of.

Outputs land in `06-deployment.md` (the environment set, the artifact, and the promotion path), in
`02-constraints.md` when the forge or the hosting platform imposes the pipeline, and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

The safe default is trunk-based development, hosted CI on the forge the code already lives on
(GitHub Actions or GitLab CI), and one immutable artifact built once per commit and promoted to
each environment by digest — never rebuilt. The default environment set is production plus one
staging that runs the same deploy path; every extra environment is drift you now maintain, data
you now seed, and money you now spend. Free tiers cover small teams comfortably in 2026: GitHub
Actions gives private repos 2,000 Linux minutes a month, GitLab Free gives 400 shared-runner
minutes a month, and self-hosted runners are unlimited and free on both.

Two boundaries keep the rest of the argument short. **GitOps is a Kubernetes pattern.** Argo CD
and Flux (both CNCF-graduated, both Apache-2.0) are the right promotion model only when you run
Kubernetes — a cluster reconciling itself to Git state is the payoff, and bolting the machinery
onto compose or a PaaS is ceremony without a reconciler. **Manual deploys have one honest
context**: one person deploying a low-stakes system they can rebuild from the repo. The moment a
second person deploys, or an auditor asks what is running in prod, they are a liability. And
promote by image digest, not tag: `latest` in production means you cannot say what is deployed,
and cannot roll it back.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Code already lives on GitHub or GitLab | hosted CI on that forge — zero new accounts, secrets stay in one place, and the free tier covers a small team |
| One developer, low-stakes system, no compliance | a manual deploy from a workstation is honest and acceptable — write down the steps and keep a tagged build |
| More than one person deploys, or anyone asks "what is in prod?" | pipeline-built, digest-tagged artifacts with a deploy log; manual deploys stop being defensible |
| Compliance includes audit | every release traceable commit → pipeline run → digest → environment; only CI, hosted or GitOps, gives you that trail |
| The deployment target is Kubernetes with more than one cluster or team | GitOps pull-based — Argo CD for the UI and multi-cluster fleet view, Flux for a lean composable toolkit |
| Builds are heavy (GPU, big Docker layers, a monorepo) or the minutes bill climbs | self-hosted runners — free on both forges, at the cost of patching and securing the runner hosts yourself |
| The team ships via PRs with heavy review and a testable UI | ephemeral preview environments per PR — integration issues caught before merge, paid for in seeding and teardown automation |
| Ops capacity is none and the deployment target is PaaS | PaaS git-push deploy — the platform is the pipeline; do not build CI machinery the platform already provides |

## Manual deploy from a workstation

- **License** not applicable.
- **Use when** one person, a low-stakes system, no audit requirement, and the deploy is scripted
  or documented well enough that the repo alone can reproduce it. Name it honestly: this is "no
  pipeline", not a lightweight one.
- **Pros** zero setup and zero CI cost; the fastest possible iteration for a solo operator; no new
  infrastructure to secure.
- **Cons** whatever is on that laptop ships, untracked local changes included; no release trail, so
  "what is running in prod" and "who deployed it" have no answer; a bus factor of one, where
  onboarding a second deployer means teaching folklore; and rollback is archaeology rather than a
  command.
- **Typical mistakes** keeping manual deploys after the second teammate arrives because it works;
  building on a workstation and calling it reproducible without a lockfile-pinned, containerized
  build; no tagged commit per release, so prod state diverges silently from Git.

## Hosted CI on the forge (GitHub Actions, GitLab CI)

- **License** proprietary SaaS with a free tier — GitHub gives 2,000 Linux minutes a month on
  private repos and unlimited on public ones; GitLab Free gives 400 shared-runner minutes a month
  per namespace.
- **Use when** the default for everyone. The code already lives on the forge, CI config is one YAML
  file in the repo, and secrets and permissions ride the forge's existing model.
- **Pros** no infrastructure to run, with runners patched for you; PR and MR integration, required
  checks and environments are built in; the free tier covers a small team's build, test and deploy
  comfortably; and there is a marketplace or catalog of reusable steps.
- **Cons** the minutes bill can climb on Windows or macOS runners and heavy matrix builds; vendor
  coupling, because workflow YAML is not portable between forges; GitLab Free's 400 minutes is
  thin enough to plan a self-hosted runner early; and a hosted-runner outage blocks releases.
- **Typical mistakes** rebuilding the image per environment instead of building once and promoting
  the same digest; deploying from CI with a long-lived admin credential in secrets instead of OIDC
  or short-lived tokens; running the full test matrix on every push to every branch and burning the
  free tier by week two; letting the deploy job diverge between staging and prod, when staging must
  run the same path.

## Self-hosted runners (on either forge)

- **License** the runner software is open source — the GitHub runner is MIT, GitLab Runner is MIT —
  and usage is free on both forges.
- **Use when** the minutes bill exceeds the cost of a VM, builds need special hardware (GPU, ARM,
  big cache disks), or builds must run inside a private network.
- **Pros** unlimited minutes at a fixed VM cost; warm caches make big builds dramatically faster;
  and the runner can reach internal-only resources such as registries and databases without
  exposing them.
- **Cons** you now patch, monitor and scale the runner hosts; a compromised runner holds your deploy
  credentials, which makes it production-adjacent infrastructure; and snowflake runner state —
  "works on the runner" — creeps in without ephemeral or containerized executors.
- **Typical mistakes** attaching self-hosted runners to public repos, where any fork PR can execute
  code on your infrastructure; long-lived pet runners with mutable state instead of ephemeral,
  per-job environments; giving the runner blanket prod credentials rather than per-environment
  scoped ones.

## GitOps pull-based (Argo CD, Flux) — Kubernetes only

- **License** both Apache-2.0, both CNCF-graduated.
- **Use when** deployment is Kubernetes and you want the cluster to reconcile itself to a
  Git-declared state: CI builds and pushes the image, bumps the digest in a config repo, and the
  in-cluster agent pulls and applies. Argo CD when you want the UI, SSO and RBAC, and a
  multi-cluster fleet view; Flux when you want a small composable engine.
- **Pros** Git is the audit log — every prod change is a commit and rollback is a revert; drift
  detection and self-healing, so manual `kubectl` edits get reverted; no CI system holds cluster
  credentials, because the agent pulls; and it scales to many clusters and teams under one
  promotion model.
- **Cons** it only pays off on Kubernetes, and on compose or PaaS it is ceremony without a
  reconciler; it is a second system to operate, upgrade and secure; the config-repo structure —
  Kustomize overlays or Helm values per environment — is real design work; and debugging "why
  didn't it sync" adds a layer between merge and prod.
- **Typical mistakes** adopting Argo CD for a single compose host because a blog said GitOps is
  best practice; tangling the app repo and the config repo together, so every image bump triggers a
  full CI run; promoting by mutable tag in the config repo, where the reconciler happily syncs
  while prod runs stale images; turning off auto-sync everywhere, which reduces GitOps to a slow
  `kubectl` with extra steps.

## PaaS git-push deploy (Railway, Render, Fly.io, Heroku, Azure App Service CD)

- **License** proprietary SaaS, priced per platform.
- **Use when** the deployment target is PaaS and ops capacity is none or limited: the platform
  builds on push, runs health checks and rolls back. The platform *is* the pipeline.
- **Pros** the fastest route from repo to URL, with zero pipeline maintenance; built-in rollback,
  TLS, logs and often preview environments per PR; and one less credential store, since the forge
  webhook is the whole integration.
- **Cons** build-on-push usually rebuilds per environment, so build-once-promote needs the
  platform's image-deploy path; platform lock-in on build process, config and pricing; and a weak
  fit for compliance-heavy audit trails compared with an explicit pipeline.
- **Typical mistakes** adding a parallel GitHub Actions deploy pipeline on top, so two systems race
  to deploy; skipping tests because the platform deploys on push, when CI checks belong before the
  push or merge that triggers the deploy; outgrowing the PaaS on background workers or private
  networking and patching around it for a year instead of migrating.

## Environment set

| Environments | What it catches | What it costs (drift, data, money) |
|---|---|---|
| prod only | nothing before users do; every deploy is a live experiment | cheapest in money, most expensive in incidents; acceptable only for solo or low-stakes systems with instant rollback |
| prod + staging (default) | deploy-path bugs, config and migration errors, integration against prod-like services — before users see them | one more environment's hosting; staging data must be seeded or anonymized; drift stays manageable because the same pipeline deploys both |
| dev / staging / prod | a shared dev sandbox for messy integration work before staging | three copies to keep in sync; a shared dev rots into "always broken" without an owner; often the least-justified tier — question it before adding it |
| + ephemeral previews per PR | reviewers see the real change running; integration and UI issues caught pre-merge | automation for spin-up and teardown, per-preview data seeding, and a real compute bill; orphaned previews leak money and secrets without enforced TTLs |

## What holds whatever you pick

- Build once per commit and promote the same artifact by image digest through every environment; a
  rebuild per environment is a different artifact wearing the same name.
- The deploy path to staging and prod must be the same code. A hand-rolled prod deploy next to an
  automated staging one means staging validates nothing.
- Prod plus one staging is the default environment set. Every additional environment must name its
  owner and what it uniquely catches, or it is drift.
- GitOps is a Kubernetes pattern: no cluster, no reconciler, no GitOps — use the forge's CI to
  deploy directly.
- Never deploy `latest` or any mutable tag to prod. If you cannot state the digest running in
  production, you cannot roll it back.
- Self-hosted runners are production-adjacent: ephemeral executors, per-environment scoped
  credentials, and never attached to public repos.
- Manual workstation deploys are a stated exception for a solo operator, not a pipeline. They
  expire the day a second person deploys or audit compliance arrives.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend hosted CI on the forge the code already
lives on, one artifact built per commit and promoted by digest, and exactly two environments —
production and a staging that shares the deploy path. Then name the trigger that would change it: a
second person deploying, an audit requirement, a Kubernetes fleet that wants a reconciler, or a
minutes bill that pays for a runner VM. Each trigger is a row in `07-risks.md` until it becomes a
decision.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: which environments exist, what
   builds the artifact, and how it is promoted.
2. State the monthly cost of each — CI minutes, extra environments, runner VMs — the ops capacity it
   assumes, and what moving off it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. An environment with no owner, a mutable tag in production, a deploy path that differs between
   staging and prod, and a long-lived deploy credential in CI secrets are rows in `07-risks.md`,
   each with an owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
