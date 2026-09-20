---
written_against: "web research 2026-08"
---

`written_against` names the tool and licence state this rubric was checked against — Terraform's
BUSL 1.1 relicensing and IBM's ownership of HashiCorp, OpenTofu's MPL-2.0 fork, Pulumi's
Apache-2.0 engine, Bicep's MIT licence, Terraform's `use_lockfile` S3 locking and the deprecation
of DynamoDB locking, and driftctl's maintenance mode. A vendor page that contradicts it means this
file is stale and needs re-research, not that the solution drifted.

# Infrastructure as code and drift — what is declared, where state lives, how reality is checked

Load this when the design touches environments, disaster recovery, deployment topology, or
anything provisioned outside the application repo. `deployment.md` decides what executes the
process and `machine-topology.md` decides how many hosts there are; this file decides whether
those hosts are declared in code, where the state describing them lives, and how you find out that
production no longer matches the declaration. `delivery-pipeline.md` owns the pipeline that runs
the apply, and `disaster-recovery.md` depends on the answer here — any DR posture above
backup-only rests on infrastructure someone can rebuild.

Outputs land in `06-deployment.md` (the tool, the state backend, the drift cadence), in
`02-constraints.md` when a licence policy narrows the tool choice, and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Everything that survives a redeploy belongs in IaC, reviewed in the same flow as application code;
click-ops is for one-off experiments that die with the day. The tool matters less than the
discipline: a declarative model, remote state with locking, and a scheduled answer to the question
"does reality still match the code?". Drift is a when, not an if — consoles, scripts and
incident-night fixes all write to production. Without detection, production becomes unreproducible
and the DR plan quietly depends on someone's memory of what they clicked.

The 2026 landscape matters mostly for licence policy. Terraform is BUSL 1.1 (source-available, not
OSI) under IBM-owned HashiCorp. OpenTofu is the MPL-2.0 Linux Foundation fork and a credible
drop-in with native state encryption. Pulumi's engine is Apache-2.0 and uses general-purpose
languages. Bicep is MIT and stateless, because Azure Resource Manager is the record.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Anything beyond one experiment box; a DR posture above backup-only | declarative IaC — a rebuild plan that is not executable code is a wish |
| Three environments that must actually match | one module set with per-environment inputs; hand-built environments diverge within weeks |
| An audit requirement on infrastructure changes | IaC in the PR flow, where the review trail is the change record |
| Multiple people touching shared infrastructure | remote state with locking (S3 `use_lockfile` since Terraform 1.10; DynamoDB locking deprecated) plus drift detection |
| An OSI-only licence policy | OpenTofu (MPL-2.0), the Pulumi engine (Apache-2.0) or Bicep (MIT) — Terraform 1.6+ is BUSL |
| An Azure-only estate | Bicep — no state file to store, lock or leak, and deployment stacks add deny-settings against manual edits |
| Kubernetes plus GitOps | Argo CD or Flux self-heal cluster drift — but only for cluster objects; the cluster, VPC and databases beneath still need IaC |
| Production changed by hands during incidents | scheduled drift detection with a decision path: revert the cloud, or codify the change |

## Click-ops

- **Use when** one-off experiments and spikes that will be deleted, and genuinely nothing else.
- **Pros** zero upfront cost and the fastest path to a running resource.
- **Cons** no record of what exists or why, so the environment is the only documentation; it is
  unreproducible, which makes DR a rebuild from memory under pressure; and there is no review, no
  diff and no rollback, so environments diverge immediately and permanently.
- **Typical mistakes** "we'll codify it later", when later never comes and the import cost grows
  with every click; a DR plan above backup-only sitting on infrastructure nobody can rebuild.

## Scripts (imperative CLI)

- **Use when** gluing steps IaC genuinely cannot express, or as a stopgap on the way to declarative.
- **Pros** versionable and reviewable, unlike clicking, with no new tool to learn.
- **Cons** not idempotent by default, so the second run either fails or duplicates; and there is no
  state, no plan or diff, and no drift answer — the script knows what it did, not what exists.
- **Typical mistakes** a directory of `create-*.sh` scripts treated as a rebuild plan that has never
  been run twice.

## Declarative IaC (Terraform, OpenTofu, Bicep, Pulumi)

- **License** Terraform BUSL 1.1 from 1.6; OpenTofu MPL-2.0; the Pulumi engine Apache-2.0; Bicep
  MIT.
- **Use when** the safe default for everything that survives a redeploy: declared desired state,
  plan or diff before apply, reviewed in the same PR flow as code.
- **Pros** reproducible environments, so DR is "run the pipeline" rather than archaeology; plan and
  what-if show the blast radius before it happens; and the PR trail is the audit trail, with one
  module set serving N environments.
- **Cons** state becomes a new critical asset (except with Bicep) — remote, locked, encrypted and
  access-controlled, because it can contain secrets; and the learning curve and refactor cost of
  state moves and imports are real.
- **Typical mistakes** state in the repo or on a laptop, which leaks secrets and loses
  infrastructure in one move; two people applying without locking, which corrupts state; codifying
  prod but leaving staging hand-built, so nothing tested resembles reality; assuming GitOps
  manifests cover infrastructure, when the cluster itself, the networks and the databases are out
  of their reach.

## IaC with drift detection

- **Use when** production that hands can touch — broad console access, incident fixes, multiple
  teams. IaC answers what should exist; only scheduled reconciliation answers whether it still does.
- **Pros** drift surfaces in hours rather than during the outage that depends on the drifted
  resource; it forces the honest per-drift decision, revert the cloud or codify the change; and it
  detects unmanaged resources, the shadow infrastructure IaC cannot see.
- **Cons** the tooling is mostly commercial — HCP Terraform, Spacelift, env0, Pulumi Cloud — and
  driftctl is in maintenance mode; and auto-remediation reverts incident-night fixes at the worst
  possible moment unless it is gated.
- **Typical mistakes** alerting on drift with no owner and no decision path, so the report becomes
  wallpaper; auto-apply on drift without excluding break-glass windows.

## Tool landscape (2026)

| Tool | Language / model | State handling | Licence note |
|---|---|---|---|
| Terraform | HCL, declarative | remote backends; S3 native locking via `use_lockfile` (1.10+), DynamoDB locking deprecated | BUSL 1.1 since 1.6 — source-available, not OSI; IBM-owned HashiCorp |
| OpenTofu | HCL, drop-in fork with native state encryption | the same backend model plus client-side state encryption | MPL-2.0, Linux Foundation |
| Pulumi | real languages (TS, Python, Go, C#) over a declarative engine | Pulumi Cloud or DIY backends (S3, Blob, GCS, local) | engine and SDKs Apache-2.0 |
| Bicep | a DSL compiling to ARM | no state file — Azure Resource Manager is the record; deployment stacks add deny-settings | MIT; Azure-only |
| Argo CD / Flux | Kubernetes manifests, GitOps reconcilers | Git is desired state, the cluster is actual; self-heal reverts drift | Apache-2.0, CNCF graduated |

## What holds whatever you pick

- Everything that survives a redeploy is in IaC, reviewed in the same PR flow as application code.
- State is production data: remote, locked, encrypted, and never in the repo.
- Terraform is not open source (BUSL 1.1 since 1.6). Under an OSI-only policy the answer is
  OpenTofu, Pulumi's engine, or Bicep.
- Drift is a when, not an if. Schedule detection and route every finding to one of two exits:
  revert the cloud, or codify the change.
- GitOps reconcilers cover cluster objects only. The cluster, the VPC and the database need IaC
  even in a pure-GitOps shop.
- All environments come from the same modules with different inputs — a hand-built staging
  validates nothing.
- Prove reproducibility the only way that counts: rebuild an environment from code, on a schedule
  or in a game day.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend declarative IaC for everything that
survives a redeploy, remote state with locking, one module set driving every environment, and a
scheduled drift check whose findings have a named owner. Pick the tool from the licence policy and
the estate — Bicep on Azure-only, OpenTofu where an OSI licence is required, Terraform where the
BUSL is accepted. Name the trigger that would change it: a licence policy landing, a second person
gaining console access, or a DR posture rising above backup-only. Each is a row in `07-risks.md`
until it becomes a decision.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the tool, where state lives,
   and whether drift is detected at all.
2. State each option's licence, its ongoing cost — commercial drift tooling, state backend, the
   hours to maintain modules — and what moving off it later costs in state migration.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `06-deployment.md`.
4. Unmanaged production resources, state stored anywhere but a locked remote backend, a hand-built
   environment beside a codified one, and drift alerts with no owner are rows in `07-risks.md`, each
   with an owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
