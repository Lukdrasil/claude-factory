---
written_against: "web research 2026-08"
---

`written_against` names the product and pricing state this rubric was checked against — the cloud
NAT gateway rates quoted below, and the Cilium and Istio egress capabilities. A cloud pricing page
that contradicts it means this file is stale and needs re-checking, not that the solution drifted.

# Egress control — stable source IPs and outbound filtering

The question: what is the outbound network posture — do partners need a stable egress IP to
allowlist, and does regulated data require egress filtering as an exfiltration control? `edge-proxy.md`
owns the inbound direction, what terminates TLS and what is publicly reachable; this file is the
mirror image, and the two are decided together. The host and node topology the egress path sits on
is `machine-topology.md`; the Kubernetes building blocks a mesh or CNI policy needs are
`containers.md`; the regimes that turn filtering from nice-to-have into a control are
`regulated-data.md`.

Outbound posture has two independent concerns that teams conflate.

The first is **source-IP stability**. Partners who allowlist your egress IPs need a static IP, which
autoscaling nodes' ephemeral IPs cannot provide. The standard fix is a cloud NAT gateway — AWS NAT
GW at roughly $0.045/hr plus $0.045/GB of data processing in us-east-1, up to $0.093/GB in some
regions; Azure NAT Gateway at roughly $35/month base plus per-GB; GCP Cloud NAT per-IP plus per-GB —
or a Kubernetes egress gateway. Cilium Egress Gateway pins pod traffic to a static node IP; Istio's
egress gateway adds L7 policy but cannot by itself enforce that all traffic uses it.

The second is **egress filtering**. Deny-by-default outbound with FQDN or L7 allowlists — Cilium
DNS-aware policies, mesh egress, or an outbound proxy — is a first-class exfiltration control for
regulated data and the main containment layer for SSRF: a service that cannot reach arbitrary hosts
cannot leak to them.

Two traps recur. The cost trap is high-volume traffic to S3 or blob storage routed through a NAT
gateway, where $0.045/GB of data processing turns a free-with-gateway-endpoint path into a
four-figure monthly bill — AWS's Provisioned NAT Gateway, with free data processing, exists
precisely because of this; use VPC gateway or private endpoints for cloud-service traffic. The
outage trap is deny-all egress silently breaking OCSP and CRL checks, package mirrors, and
telemetry.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Partners or webhook receivers allowlisting your source IPs | a NAT or egress gateway with documented static IPs — never today's node IP |
| Compliance treats egress as an exfiltration channel (PCI DSS 1.3.x outbound restriction, HIPAA, residency) | deny-by-default outbound with FQDN/L7 allowlists |
| Autoscaling with ephemeral node or pod IPs | any IP promise needs a NAT or egress gateway in front |
| High GB/month through the NAT path | gateway or private endpoints for cloud-storage traffic; evaluate provisioned NAT pricing |
| Services fetching user-supplied URLs (SSRF exposure) | egress containment shrinks the blast radius to the allowlist |

## Ephemeral egress IPs accepted (no static egress, no filtering)

- **Use when** no partner allowlists your IPs, there is no regulated-data exfiltration requirement,
  and outbound calls go to public APIs that do not care about the source IP. The correct default for
  most internal tools and early-stage products.
- **Pros** zero cost and zero moving parts; no NAT gateway data-processing fees; nothing to keep in
  sync when infrastructure scales.
- **Cons** you cannot promise partners a stable IP, and retrofitting one later means rerouting all
  egress; there is no exfiltration control, so a compromised service can reach any host; and the
  SSRF blast radius is the whole internet.
- **Typical mistakes** promising a partner "our IP is x.x.x.x" by reading the current node's public
  IP, after which autoscaling replaces that node and the webhook silently starts failing the
  receiver's allowlist; discovering the static-IP requirement in a partner's security questionnaire
  after go-live.

## Cloud NAT gateway for static egress (AWS NAT GW / Azure NAT Gateway / GCP Cloud NAT)

- **Use when** partners or webhook receivers allowlist your source IPs, or you need a small,
  documentable set of egress IPs for security reviews. The managed default on all three clouds.
- **Pros** truly static, documentable egress IPs — an EIP or public IP prefix — that survive
  autoscaling; managed and zone-redundant, with no instances to patch; and a simple mental model,
  where all private-subnet egress exits via known IPs.
- **Cons** a data processing fee on every GB (AWS around $0.045/GB, region-dependent up to about
  $0.093/GB) on top of the hourly charge and normal egress; it provides IP stability but zero
  filtering, so it is not a security control over what hosts are reachable; and per-AZ deployment is
  needed to avoid cross-AZ charges and single-AZ failure.
- **Typical mistakes** routing high-volume S3, blob or registry traffic through the NAT gateway
  instead of VPC gateway endpoints or Private Link — the classic surprise bill; treating the NAT
  gateway as an egress security control, when it stabilises the source IP and does not restrict
  destinations; not evaluating AWS Provisioned NAT Gateway (per-Gbps-hour, free data processing)
  once volume makes per-GB pricing dominant.

## Deny-by-default egress plus FQDN filtering

- **Use when** regulated data — PCI, HIPAA, residency — where outbound is an exfiltration channel,
  or services that fetch user-supplied URLs and need SSRF containment. Implement it via DNS-aware
  CNI policies (Cilium FQDN rules), an egress proxy, or cloud firewall FQDN rules.
- **Pros** real exfiltration control, since compromised code cannot reach unlisted hosts; it
  directly satisfies PCI-style outbound-restriction expectations and shrinks the SSRF blast radius
  to the allowlist; and FQDN rules survive endpoint IP churn that raw IP allowlists cannot.
- **Cons** allowlist maintenance is perpetual, because SaaS endpoints, CDNs and mirrors change;
  DNS-based enforcement has edge cases, notably TLS SNI versus DNS answers and wildcard-heavy CDNs;
  and every new integration needs a policy change, which teams route around if the process is slow.
- **Typical mistakes** deny-all egress silently breaking OCSP and CRL checks (TLS handshake stalls),
  OS package mirrors and telemetry, where the failures show up as mysterious timeouts weeks later;
  allowlisting by IP for services behind CDNs whose IPs rotate; turning on deny-by-default in
  production without a log-only or audit phase to discover the actual egress destinations first.

## Service mesh / Kubernetes egress gateway (Cilium Egress Gateway, Istio egress gateway)

- **Use when** Kubernetes with a mesh or Cilium already in place, needing both static egress IPs per
  workload and L7 or identity-aware egress policy — for example, only the payment service may reach
  the PSP, exiting from a pinned IP.
- **Pros** a static egress IP per namespace or workload, not just per cluster; Istio egress adds L7
  policy — per-hostname, per-service-identity rules and egress observability; and it combines IP
  stability and filtering in one layer, with no per-GB cloud NAT processing fee for in-cluster paths.
- **Cons** meaningful operational complexity, since CNI or mesh expertise is required and egress
  gateway nodes become critical infrastructure; Istio alone cannot guarantee traffic uses the egress
  gateway, because a workload bypassing the sidecar exits directly, so a NetworkPolicy backstop is
  needed; and gateway node failover for the pinned IP must be designed and tested.
- **Typical mistakes** assuming the Istio egress gateway is a security boundary without a
  default-deny NetworkPolicy forcing traffic through it; running the egress gateway on a single node,
  so the "static IP" disappears with the node; adopting a mesh solely for static egress when a cloud
  NAT gateway would do.

## What holds whatever you pick

- Never promise a partner a source IP that is not behind a NAT or egress gateway — autoscaling node
  IPs are ephemeral.
- Route cloud-storage traffic via gateway or private endpoints, never through the NAT gateway;
  $0.045/GB adds up fast.
- Egress filtering rollouts start in log-only mode: explicitly allowlist OCSP and CRL endpoints,
  package mirrors and telemetry before enforcing.
- A NAT gateway is an addressing feature; deny-by-default filtering is the security control —
  regulated data needs the latter.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend accepting ephemeral egress IPs with no
filtering, which is the correct default for an internal tool or an early-stage product with no
partner allowlist and no regulated data. Name the triggers that would change it — the first partner
that allowlists source IPs, the first regulated data class, the first service that fetches a
user-supplied URL, the first month where NAT data processing shows up on the bill — as rows in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: whether any partner
   requires a documented source IP, whether a regime treats outbound as an exfiltration channel, and
   how many GB per month the egress path is expected to carry.
2. State the recurring cost of each — the NAT gateway's hourly and per-GB charges, the perpetual
   allowlist maintenance, the mesh or CNI expertise the gateway option assumes — and what
   retrofitting a static IP later costs, which is rerouting all egress.
3. Write the accepted posture as an ADR under `docs/adr/`, the rejected options as alternatives with
   the reason each lost, and reference it from `06-deployment.md` beside the network topology, with
   the documented egress IPs recorded where partners can be pointed at them.
4. Numbers become `QS-` rows: the documented egress IP set, expected GB/month through the NAT path
   and its cost, and the time to add a destination to the allowlist. An unfiltered egress path under
   a regulated data class, an egress gateway on a single node and an IP promised from a node's
   current address are `R-` rows in `07-risks.md` with an owner. Anything the human leaves open is a
   `TODO(question)` per `templates.md`.
