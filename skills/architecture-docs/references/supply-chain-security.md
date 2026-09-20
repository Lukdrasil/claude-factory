---
written_against: "web research 2026-08"
---

`written_against` names the regulatory and tooling state this rubric was checked against — the EU
CRA's dates and penalty ceilings, and the OSS tools and licences named below. A regulation page or
a project `LICENSE` that contradicts it means this file is stale and needs re-checking, not that
the solution drifted.

# Supply-chain security — dependencies, artifacts, and knowing what you shipped

The question this file grades: how much of the dependency-and-artifact pipeline is automated — CVE
scanning, SBOM per release, signed provenance — and can you answer "are we affected?" within an
hour of the next Log4Shell? `security.md` records the supply-chain *policy* as one of the five
hardening decisions with architectural consequences; this file is where that policy becomes tiers,
tools and a regulatory deadline. The pipeline that enforces it is `delivery-pipeline.md`; the licence
family question for any dependency the scan surfaces is `licensing.md`; image digests, base images
and rebuild cadence land in `containers.md`.

Supply-chain security is graduated, not binary. Automated dependency updates plus a CVE scanner is
the cheap floor. An SBOM per release turns "are we affected?" from a week of grepping into a
database query. Signed provenance — cosign, SLSA — stops a compromised pipeline from shipping
under your name. The safe default is boring and mostly free: Renovate or Dependabot,
Trivy or Grype in CI failing on known-exploited criticals, an SBOM (CycloneDX or SPDX) emitted per
build and stored with the release, images promoted by digest and signed with cosign. The failure
mode this exists to prevent: a vulnerable or trojaned dependency ships unnoticed, and when the CVE
lands you cannot enumerate which deployed versions contain it.

The EU Cyber Resilience Act makes this regulatory rather than optional for anything commercially
placed on the EU market. Vulnerability-reporting obligations bite from 11 September 2026 —
a 24-hour early warning to ENISA and the CSIRT. Full conformity, including CE marking and an
SBOM-backed vulnerability-handling process, applies from 11 December 2027, with fines up to
EUR 15M or 2.5% of global turnover.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| You cannot say today which releases contain a given library version | SBOM per release, stored and queryable — the minimum that makes incident response an hour instead of a week |
| Product commercially placed on the EU market | CRA scope: reporting process before 11 Sept 2026, SBOM and vulnerability handling before 11 Dec 2027 — start at the SBOM tier now |
| Dependencies updated manually, when someone remembers | Renovate or Dependabot — automated PRs are the only cadence that survives a busy team |
| Images referenced by mutable tag across environments | promote by digest; a tag makes "what runs in prod" unanswerable |
| Base images rebuilt rarely | scheduled weekly rebuild — most container CVEs are fixed by rebuilding on a patched base, not by touching your code |
| Anyone with CI access could push an image the cluster will run | cosign signing in CI plus verification at admission |
| Customer security questionnaires ask for build provenance | SLSA-style attestation — Build L2 falls out of hosted runners nearly for free |
| No ops capacity | still do scanning and SBOM — both are CI-only, with zero runtime footprint |

## Nothing automated

- **Use when** honest only for a throwaway prototype that will never hold real data or be sold.
- **Pros** zero setup cost.
- **Cons** the next Log4Shell means grepping lockfiles by hand across every repo and release;
  dependencies rot until upgrading is a rewrite; under the CRA this is indefensible for a product
  on the EU market; and you cannot distinguish "not affected" from "don't know".
- **Typical mistakes** calling a quarterly manual `npm audit` a process; assuming the cloud
  registry scan covers application dependencies; deferring "until we have customers" — retrofitting
  an inventory across old releases is the expensive order.

## Scanning only (Renovate/Dependabot plus a CVE scanner)

- **License** Renovate is AGPL or hosted; Trivy and Grype are Apache-2.0.
- **Use when** the pragmatic floor for any real project: automated update PRs plus a scanner in CI
  failing on known-exploited criticals. All free OSS, an afternoon to wire.
- **Pros** catches the bulk of known-CVE risk for near-zero ongoing cost; a short upgrade path
  makes patching under pressure a version bump rather than a migration; and it scans built images
  too, covering OS packages in the base image.
- **Cons** no release inventory — it tells you today's HEAD is affected, not which shipped versions
  are; and nothing prevents a compromised artifact from being deployed.
- **Typical mistakes** merging Renovate PRs blind without trustworthy tests; scanning only source
  and not the built image; letting the scanner warn instead of fail, after which everyone learns to
  ignore it.

## Scanning plus SBOM per release

- **License** syft is Apache-2.0; CycloneDX is ECMA-424 and SPDX is ISO/IEC 5962.
- **Use when** the safe default for anything with paying users, and the tier CRA-scoped products
  must reach: every build emits an SBOM from the final image, stored with the release artifact.
- **Pros** "are we affected?" becomes a query over stored SBOMs; it serves CRA vulnerability-handling
  expectations and every enterprise questionnaire; and continuous re-scan of stored SBOMs
  (Dependency-Track class) catches CVEs disclosed after shipping.
- **Cons** an SBOM nobody stores or re-scans is compliance theatre — the value is in the query, so
  it needs a home; and there is still no integrity guarantee that the artifact is the one CI built.
- **Typical mistakes** generating the SBOM from source instead of the final image, which leaves OS
  packages and build-time injections invisible; emitting it and attaching it to nothing, losing the
  release-to-SBOM mapping.

## Scanning, SBOM and signed provenance (cosign/SLSA class)

- **License** cosign and Sigstore are Apache-2.0.
- **Use when** regulated or high-value targets, many teams pushing to shared clusters, or a threat
  model that includes the CI pipeline itself. Images signed (keyless via OIDC), provenance
  attested, verified at admission.
- **Pros** a compromised laptop or leaked registry credential can no longer put an artifact into
  prod, because admission rejects unsigned images; SLSA Build L2 falls out of GitHub Actions or
  GitLab CI with modest wiring; and digest-pinned, signed, attested artifacts make the
  deploy-to-source chain auditable end to end.
- **Cons** a real ops surface — key and identity policy, admission controller lifecycle, a
  break-glass procedure; and admission verification is a Kubernetes concept, so elsewhere the
  deploy script verifies and the guarantee is only as strong as that script.
- **Typical mistakes** signing images but never enforcing verification anywhere, which is
  decoration; long-lived signing keys in CI secrets where keyless OIDC is available; buying SLSA L3
  ambitions before scanning and SBOM basics exist.

## EU CRA timeline

| Date | Obligation | Practical consequence |
|---|---|---|
| 10 Dec 2024 | Entered into force; transition running | Products designed now should be designed against Annex I |
| 11 Sept 2026 | Art. 14 reporting: exploited vulnerabilities — early warning to ENISA/CSIRT within 24h, notification 72h, final report 14 days | You need a monitored intake and the ability to tell within hours whether a CVE affects shipped versions — in practice, SBOMs per release, now |
| 11 Dec 2027 | Full application: CE marking, conformity assessment, coordinated disclosure policy, security updates for the support period | No conformity, no EU market; fines to EUR 15M or 2.5% of global turnover |

## Tool map

| Concern | OSS tool | Where it runs |
|---|---|---|
| Automated dependency update PRs | Renovate or Dependabot | Repo level, continuous PRs |
| CVE scan of code, lockfiles, images | Trivy or Grype (plus OSV-Scanner) | CI on every build; fail on exploited/critical |
| SBOM generation | syft or trivy (CycloneDX/SPDX) | CI after image build, from the final image; attach to release |
| SBOM storage and re-scan | Dependency-Track; or nightly Grype over stored SBOMs | Server or scheduled CI job |
| Artifact signing | cosign (keyless OIDC or KMS) | CI, immediately after push, signing the digest |
| Verification at admission | Kyverno `verifyImages` / Sigstore policy-controller | K8s admission; non-k8s: verify in the deploy step |
| Base image currency | Renovate digest pinning plus scheduled rebuild | Weekly floor |

## What holds whatever you pick

- The question that grades your supply chain: "which shipped versions contain library X?" If
  answering takes more than an hour, you are at tier nothing, whatever tools are installed.
- Scanning is a statement about today; SBOMs are a statement about everything you ever shipped —
  CVEs are disclosed against artifacts already in production.
- Promote images by digest, never by tag: a mutable tag silently defeats both scanning and signing.
- Signing without admission-time (or deploy-time) verification is decoration; the enforcement
  policy is the control.
- Most container CVEs are fixed by rebuilding on a patched base image — a weekly rebuild cadence
  outperforms heroic patching.
- CRA reporting starts 11 September 2026 and covers products already on the market: the SBOM work
  has a regulatory deadline, not a someday.
- Climb the ladder in order — scanning, then SBOM, then signed provenance. Each tier is cheap given
  the one below and incoherent without it.

## When the evidence is thin

If nothing recorded distinguishes the tiers, recommend the scanning-plus-SBOM floor: Renovate or
Dependabot on the repo, Trivy or Grype failing the build on known-exploited criticals, an SBOM
generated from the final image and attached to the release, images promoted by digest, and a weekly
base-image rebuild. Name the trigger that would add signed provenance — the first paying customer
asking for build provenance, a shared cluster several teams can push to, a threat model that
includes CI itself — as a row in `07-risks.md`. If the product will be placed on the EU market, the
CRA dates are not a trigger to wait for; they are a `C-` constraint already.

## Recording the choice

1. Put the tiers to the human against the affected `QS-` and `C-` ids: which tier the product is
   at today, which one its market and data class require, and what the gap costs to close.
2. State the recurring cost of each — the CI minutes, the SBOM store, the admission controller and
   its break-glass path — and what deferring it costs, which for the inventory tiers is
   retrospective archaeology across old releases.
3. Write the accepted tier as an ADR under `docs/adr/`, the rejected tiers as alternatives with the
   reason each lost, and reference it from `06-deployment.md` beside the pipeline that enforces it.
4. Numbers become `QS-` rows: time to answer "which releases contain X", time to patch a critical
   dependency, base-image rebuild cadence, the CRA 24/72-hour reporting windows if in scope. An
   unscanned dependency path, an SBOM with no home, and a signature nobody verifies are `R-` rows
   in `07-risks.md` with an owner. Anything the human leaves open is a `TODO(question)` per
   `templates.md`.
