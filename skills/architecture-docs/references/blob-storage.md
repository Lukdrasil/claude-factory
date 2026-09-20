---
written_against: "web research 2026-08"
---

`written_against` names the product state this rubric was checked against — which self-hosted
object stores are still maintained, and what the cloud stores offer as configuration. A vendor page
that contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Blob storage — where uploaded files live, how they get in, how they come back out

Load this when the system accepts user uploads or generates files that must survive a redeploy.
`data.md` decides the stores that hold copies of rows; this file decides the store that holds
bytes, which is a different problem with different failure modes. `operations.md` owns the backup,
retention and encryption obligations of whatever store is chosen, and `security.md` owns whether
the files carry personal data at all.

Outputs land in `03-containers.md` (the store as a unit, with the app as its writing owner), in
`06-deployment.md` (the bucket, its public-access posture, its lifecycle rules and the CDN in front
of it), and in an ADR per `templates.md`.

Files are not rows. They need durability, a path in, and a path out, and each of those three is
decided separately. The **store** decides durability — cloud object store, self-hosted object
store, filesystem volume, or none at all. The **upload path** decides who carries the bytes: the
app proxying them, or the client shipping them direct to the store against a presigned URL with
size and type conditions signed in. The **serving path** decides who carries them back: signed read
URLs, a CDN with its own signing, or the app proxying again. The safe default is a cloud object
store with presigned uploads and signed read URLs, where the app brokers permissions and never
touches the bytes.

The failure mode this rubric exists to block: files written to one VM's local disk, gone on the
next redeploy, and silently split across machines the moment a second replica appears.

One 2026 fact changes the self-hosted answer. MinIO's community edition was archived in February
2026, so "MinIO class" now means SeaweedFS, Garage, or Ceph RGW at scale.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| No user uploads, no generated files | none needed — do not provision a bucket for a system of rows and logs |
| Cloud deployment, or more than one replica planned | cloud object store, presigned uploads |
| Single machine, small files, one replica forever, backups solved | filesystem volume — eyes open |
| Data residency or a no-cloud constraint plus real ops capacity | self-hosted object store (SeaweedFS, Garage) |
| Large files or many concurrent uploads | presigned direct-to-store — keep the bytes off the app servers |
| Uploads must be inspected or authorised per-byte before existing | via-app upload, or presigned plus quarantine-scan-promote |
| Files served to many users | CDN with its own signing, bucket locked to the CDN |
| Untrusted uploads later opened by other users | malware scanning on write (GuardDuty for S3, Defender for Storage, a ClamAV pipeline) |

## None needed

- **Use when** the system stores no files.
- **Pros** nothing to secure, back up or pay for, and no upload attack surface.
- **Cons** the first real file feature lands as a hack unless the decision is revisited.
- **Typical mistakes** storing images or PDFs as base64 in the database because "we do not have blob
  storage"; letting a "temporary" local-disk upload folder become load-bearing.

## Filesystem volume

- **Use when** single machine, single replica, small scale, and the deployment guarantees the volume
  outlives the container — a mounted Docker volume or a VM disk, never a PaaS filesystem. An honest
  answer for an internal tool with a backup job.
- **Pros** zero new infrastructure, trivial to reason about, fast local reads.
- **Cons** it breaks at two replicas, because uploads land on whichever replica took the request. On
  PaaS the filesystem is ephemeral and files vanish on every redeploy. Durability is exactly your
  backup job and nothing more, and there are no signed URLs, so every upload transits the app.
- **Typical mistakes** writing to the container filesystem instead of a mounted volume, where the
  first redeploy deletes everything; reaching for NFS between replicas as the fix, which re-adds a
  single point of failure plus the locking semantics object stores were built to avoid.

## Self-hosted object store (SeaweedFS / Garage class)

- **License** SeaweedFS Apache-2.0; Garage AGPLv3; MinIO community archived February 2026 (AGPLv3,
  successor is the paid AIStor). The licence family question itself belongs to `licensing.md`.
- **Use when** data residency or a no-cloud mandate is recorded as a real constraint, and someone
  owns operating a storage product: disks, upgrades, replication, monitoring, capacity.
- **Pros** an S3-compatible API, so app code and presigned flows are identical to the cloud path;
  data stays on your hardware, with no egress or per-request fees.
- **Cons** you own durability — disk failure, bit rot, replication, and backup and restore drills are
  your pager. A single-node self-hosted store is a filesystem volume in an S3 costume; durability
  starts at multi-node.
- **Typical mistakes** picking MinIO community edition in 2026, which is unmaintained — pick
  SeaweedFS or Garage, or Ceph RGW at scale; running one node with one disk and calling it durable;
  choosing self-hosting to save money with no ops capacity, where the first lost weekend costs more
  than a year of S3.

## Cloud object store (S3 / Azure Blob / GCS)

- **Use when** the default for anything on a cloud, and for anything that will ever run two replicas.
- **Pros** eleven-nines durability, with versioning and replication as configuration. Presigned or
  SAS uploads let the app sign a permission slip while the client ships bytes straight to the store.
  Lifecycle rules — expire temp uploads, tier cold data — are bucket config. Managed malware scanning
  exists on-platform, and CDN integration comes with its own signing.
- **Cons** egress and per-request costs at volume, where a hot public bucket behind no CDN is a bill;
  a misconfigured public bucket is the classic breach, so block public access at the account level.
- **Typical mistakes** proxying every upload through the app "for simplicity", which hits body-size
  limits and doubles bandwidth; a presigned PUT with no constraints — use presigned POST with
  `content-length-range` and an exact content-type, a short expiry and server-generated object keys;
  trusting the client's declared type, when the honest path is to sniff magic bytes at promote and
  set `Content-Disposition` on serve so an HTML upload cannot XSS your domain.

## Store options against the deciding concerns

| Concern | Filesystem volume | Self-hosted object store | Cloud object store |
|---|---|---|---|
| Durability | your backup job, nothing else | yours to engineer: multi-node, erasure coding, drills | designed-for eleven nines as config |
| Two or more replicas | breaks — uploads split across nodes | works — it is a network service | works — that is the point |
| Presigned upload/read URLs | none — the app proxies every byte | yes — S3-compatible signing | yes — native |
| Lifecycle rules | cron jobs you write and forget | partial to DIY | bucket configuration |
| Cost shape | free until the incident | hardware plus unbudgeted ops time | cents per GB-month plus egress |

## Upload path: via app vs presigned direct

| Concern | Via app (proxy) | Presigned direct-to-store |
|---|---|---|
| Bytes cross | client → app → store — bandwidth paid twice | client → store — the app signs and steps aside |
| Size/type enforcement | in your handler code | signed into the URL; verify magic bytes at promote |
| Large files | body limits, timeouts, replica memory pressure | store handles it; multipart for very large |
| Synchronous inspection | natural — you hold the stream | upload to a quarantine prefix, scan, promote |
| Honest default | small files, low volume, mandatory in-line inspection | everything else |

## What holds whatever you pick

- The default is a cloud object store, presigned POST uploads with size and type conditions, signed
  read URLs, and block-all-public-access on.
- Never write user files to a replica's local disk in anything cloud-deployed: data loss on the next
  redeploy, split-brain at the second replica.
- "Self-hosted MinIO" is a 2024 answer. Community MinIO is archived, so self-hosted now means
  SeaweedFS or Garage, and it is a storage product someone must operate.
- Presigned discipline: POST over bare PUT, `content-length-range` and an exact content-type signed
  in, expiry in minutes, server-generated object keys.
- Uploads later opened by other users get scanned, are served with `Content-Disposition: attachment`,
  and never from your app's origin.
- Per-user presigned GETs defeat CDN caching, because every signature is a distinct URL. Once the
  same file goes to many users, use the CDN's own signing.
- Lifecycle rules are part of the design: expire the quarantine prefix, expire abandoned multipart
  uploads, tier or delete old exports.
- The database stores the object key and metadata; the store stores the bytes. Never both, never
  neither.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a cloud object store with presigned POST
uploads and signed read URLs, block-all-public-access on, and no CDN until the same file is served
to many users. Name the trigger that would change it — a residency constraint, a second replica
arriving on a filesystem volume, an untrusted upload that another user will open — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which store holds the bytes,
   which path carries them in, and which path serves them back.
2. State the recurring cost of each — storage and egress, the hardware and ops time of a self-hosted
   store, the incident a filesystem volume is one redeploy away from — and what reversing it later
   costs once objects exist.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. A bucket with no lifecycle rules, an unscanned upload path serving files from the app's own
   origin, and a filesystem volume with no proven restore are rows in `07-risks.md`. Anything the
   human leaves open is a `TODO(question)` per `templates.md`.
