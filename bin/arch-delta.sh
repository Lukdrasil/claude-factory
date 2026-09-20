#!/bin/sh
# arch-delta.sh — the deterministic half of the semantic-drift check of docs/design/architecture-model.md
# § Enforcement. Read-only, no LLM: it exports the LikeC4 model of the working tree and of <base-ref> and prints
# the elements and relations that appeared, vanished or changed kind/technology between them. Whether a change
# needed a doc edit, which document owns it, or whether the model is *true* stays a human answer — the script
# says what moved, it never decides and never fixes. A repo with no docs/architecture/*.c4, or a machine with no
# likec4 on PATH, is skipped, the same rule as doc-facts.sh.
set -eu

usage() {
  echo "usage: arch-delta.sh <product-repo> <base-ref>" >&2
  exit 2
}

[ $# -eq 2 ] || usage
case "$1" in -h|--help) usage ;; esac
repo=$(CDPATH= cd -- "$1" 2>/dev/null && pwd) || { echo "arch-delta.sh: '$1' is not a directory" >&2; exit 2; }
base=$2
cd "$repo"

if ! ls docs/architecture/*.c4 >/dev/null 2>&1; then
  echo "arch-delta.sh: '$repo' has no docs/architecture/*.c4 — no model to diff, skipped."
  exit 0
fi
if ! command -v likec4 >/dev/null 2>&1; then
  echo "arch-delta.sh: no likec4 on PATH — nothing to export, skipped."
  exit 0
fi

tmp=$(mktemp -d)
trap 'git -C "$repo" worktree remove --force "$tmp/base" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

likec4 export json -o "$tmp/head.json" --skip-layout docs/architecture >/dev/null 2>&1 \
  || { echo "arch-delta.sh: likec4 could not export the working tree model" >&2; exit 1; }

git worktree add --detach "$tmp/base" "$base" >/dev/null 2>&1 \
  || { echo "arch-delta.sh: cannot check out base ref '$base'" >&2; exit 2; }

# A base with no .c4 files is an empty model, so every element of the working tree reads as added.
if ls "$tmp/base"/docs/architecture/*.c4 >/dev/null 2>&1; then
  likec4 export json -o "$tmp/base.json" --skip-layout "$tmp/base/docs/architecture" >/dev/null 2>&1 \
    || { echo "arch-delta.sh: likec4 could not export the model at '$base'" >&2; exit 1; }
else
  printf '{"elements":{},"relations":{}}\n' > "$tmp/base.json"
fi

# `likec4 export json` keys .elements by element id (each with .id, .kind and an optional .technology) and
# .relations by relation id (each with .source.model and .target.model).
jq -r -n --slurpfile a "$tmp/base.json" --slurpfile b "$tmp/head.json" '
  ($a[0].elements // {}) as $ae | ($b[0].elements // {}) as $be |
  ($a[0].relations // {}) as $ar | ($b[0].relations // {}) as $br |
  def ends($r): "\($r.source.model // $r.source) -> \($r.target.model // $r.target)";
  ($be | keys[] as $k | select($ae[$k] == null) | "+ element \($k) (\($be[$k].kind))"),
  ($ae | keys[] as $k | select($be[$k] == null) | "- element \($k) (\($ae[$k].kind))"),
  ($be | keys[] as $k | select($ae[$k] != null) |
    (if $ae[$k].kind != $be[$k].kind then "~ element \($k) kind \($ae[$k].kind)→\($be[$k].kind)" else empty end),
    (if ($ae[$k].technology // null) != ($be[$k].technology // null)
       then "~ element \($k) technology \($ae[$k].technology // "-")→\($be[$k].technology // "-")" else empty end)),
  ($br | keys[] as $k | select($ar[$k] == null) | "+ relation \(ends($br[$k]))"),
  ($ar | keys[] as $k | select($br[$k] == null) | "- relation \(ends($ar[$k]))")
'
exit 0
