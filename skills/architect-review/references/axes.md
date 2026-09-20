# The five axes

Every finding is drawn from one of these. The evidence, severity and report rules are in `checks.md`, and
stale documentation is `drift.md`.

## 1. Architecture fit

Does what the plan builds fit the system that is documented? Read `01-context.md`, `02-constraints.md`,
`03-containers.md`, `04-quality-scenarios.md`.

Findings: a new deployable unit or external system in no container or context table; a constraint from
`02-constraints.md` the plan breaks; a change that breaks a quality scenario's measure with no matching
update to that scenario; a scenario the plan claims to serve that does not exist.

**Done when** every container, external system and constraint the plan touches is matched against its row,
and each one either matches or is a finding.

## 2. Boundary-respecting cut

Is the work cut along the documented boundaries? Mostly a `cut-check` axis; on `plan-check` it applies to
`## Proposed tasks`.

Findings: one task changing two containers the docs keep separate to deliver one behaviour; a task cut along
layers instead of a verifiable behaviour; a documented module with no owner among the tasks that change it;
an acceptance that can only run once another task is finished.

**Done when** every proposed task maps to a named container in `03-containers.md`, or to a cross-cutting
concern the docs record, or a finding says why it maps to neither.

## 3. Dependency direction

Do the new edges point the way the documented structure says they may? Read the `Talks to` column of
`03-containers.md` and its `## Structure inside`, plus the ADR that fixed the internal style.

Findings: an inner layer importing an adapter, a framework or a persistence type; a container calling one
that the table already has calling it, a new cycle; a call crossing a module boundary the docs enforce; a new
edge that is real but recorded nowhere.

**Done when** every direction the plan introduces is checked against `Talks to` and the container's internal
style, citing the ADR that decided it.

## 4. Contract collisions

Public contracts: HTTP endpoints, CLI flags, config keys, database schemas, event payloads, shared files.
Read each proposal's context and acceptance, then grep the repo for the names they touch.

Findings: two proposals changing one contract with no ordering between them; a proposal changing a contract
another proposal reads while `depends_on` is empty; a contract another container owns; a new contract whose
name already means something else in `CONTEXT.md`.

**Done when** every public contract named by more than one proposal is listed, with either an ordering or a
finding.

## 5. ADR contradictions

Read the accepted ADRs governing the area the plan touches.

Findings: the plan reverses an accepted decision without proposing a superseding ADR; it re-decides a
question an ADR already closed; it depends on an ADR that is `superseded` or `rejected`. A deliberate
reversal is fine, it just has to arrive as a proposed ADR rather than a silent change.

**Done when** every accepted ADR governing the touched area is read and either cited as satisfied or raised
as a finding.
