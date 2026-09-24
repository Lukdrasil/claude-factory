#!/bin/sh
# Writes a new task straight into a state clone, which in the standalone posture (ADR-0050) is how every task
# comes into being: the id and slug computed the way TaskWriter computes them, the frontmatter validated against
# docs/design/task-format.md (TaskSchema + TaskWriter.Validate), then one commit. A clone without an origin
# stays local. A clone with an origin syncs first and pushes after, all under the state lock of lib-tasks.sh:
# the id is one more than the highest id taken, so two machines on one state remote could otherwise both hand
# out the same number. After a push the remote refuses it fetches: when its commit is already upstream (another
# session in this clone pushed it) the task landed and its id is printed. Otherwise it drops only its own commit
# with `reset --keep`, which keeps every uncommitted edit, and only while HEAD is still that commit, syncs,
# recomputes the id and tries again, three times at most (the ADR-0012 recipe; the third failure, or a HEAD
# that moved, leaves the commit in the clone, unpushed, and says so).
#
#   task-new.sh --repo <key> [--parent T-NNN] [--slug <slug>] [--status claimed --owner <owner>] [--state <dir>] --file <markdown>
#
# cwd = the state clone unless --state. Prints {"id":…,"file":…} like POST /api/tasks; a refusal is exit 1 with
# the reason on stderr and nothing written. `--status claimed --owner` is the one divergence from the API: a
# block a standalone session cuts for itself is born claimed by that session.
set -eu

repo='' parent='' slug='' status=draft owner='' state='' file=''
die() { printf 'task-new: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--parent|--slug|--status|--owner|--state|--file)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --repo) repo=$2 ;;
        --parent) parent=$2 ;;
        --slug) slug=$2 ;;
        --status) status=$2 ;;
        --owner) owner=$2 ;;
        --state) state=$2 ;;
        --file) file=$2 ;;
      esac
      shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -n "$repo" ] || die "--repo <key> is required"
[ -n "$file" ] || die "--file <markdown> is required"
[ -f "$file" ] || die "no such file: $file"
[ -n "$state" ] || state=$(pwd)
[ -d "$state/.git" ] || die "$state is not a state clone — run from one or pass --state <dir>"

# state_commit is shared with task-approve.sh and state-report.sh
. "$(dirname -- "$0")/lib-tasks.sh"
case "$status" in
  draft) ;;
  claimed) [ -n "$owner" ] || die "--status claimed needs --owner <owner>" ;;
  *) die "--status may only be claimed (with --owner); a new task is draft otherwise" ;;
esac

# a block write is held to the architect verdict of the plan it names, before anything is synced or
# committed; the block id is not allocated yet, so the quick-verdict lookup by id stays the Write branch's alone.
# Top-level writes are not checked (Q7).
if [ -n "$parent" ]; then
  av_rc=0
  av_msg=$(architect_verdict "$repo" "$(plan_slug < "$file")" '') || av_rc=$?
  case "$av_rc" in
    0) ;;
    2) printf 'task-new: %s\n' "$av_msg" >&2 ;;
    *) die "$av_msg" ;;
  esac
fi

has_origin=0
git -C "$state" remote get-url origin >/dev/null 2>&1 && has_origin=1
# the ids other machines already took, before this one picks the next; never fatal, an unreachable remote
# leaves the local view (and the push below reports it)
sync_state() { [ "$has_origin" = 1 ] && git -C "$state" pull -q --rebase --autostash -X theirs >/dev/null 2>&1 || :; }

assign_and_commit() {
# every id already taken, across every repo — the next T-NNN or T-NNN-NN is one more than the highest. One `id:`
# per file, the first one: a task body may quote an `id:` line of its own (a frontmatter example, a diff), and
# over the concatenated files that quote would count as a taken id and skip a number.
ids=$(for f in "$state"/repos/*/tasks/*.md; do
  [ -f "$f" ] || continue
  sed -n 's/^id:[[:space:]]*//p' "$f" | head -n1
done | sed 's/[[:space:]]*#.*//')

# ponytail: node is already a hard dependency of every session (policy-guard.sh); one process computes the id,
# inserts it into the branch, fills the bookkeeping defaults, validates and slugs. stdout = id, slug, markdown.
res=$(IDS=$ids REPO=$repo PARENT=$parent SLUG=$slug STATUS=$status OWNER=$owner TODAY=$(date +%F) node -e '
const e=process.env;let s="";
process.stdin.on("data",d=>s+=d).on("end",()=>{
  const fail=m=>{process.stderr.write("task-new: "+m+"\n");process.exit(1)};
  s=s.replace(/\r\n/g,"\n");
  const fence=L=>{for(let i=1;i<L.length;i++)if(L[i].trimEnd()==="---")return i;return -1};
  const parse=t=>{const f={};if(!t.startsWith("---"))return f;const L=t.split("\n"),end=fence(L);if(end<0)return f;
    for(let i=1;i<end;i++){const l=L[i];const c=l.indexOf(":");if(c<0||!l.length||/^\s/.test(l)||l[0]==="#")continue;
      const k=l.slice(0,c).trim();if(!k)continue;const v=l.slice(c+1).split(" #")[0].trim().replace(/^[\x27"]|[\x27"]$/g,"");f[k]=v==="null"?"":v}
    return f};
  const set=(t,k,v)=>{const L=t.split("\n"),end=fence(L);if(end<0)return t;
    for(let i=1;i<end;i++){const c=L[i].indexOf(":");if(c<0||/^\s/.test(L[i]))continue;const n=L[i].slice(0,c);if(n.trim()!==k)continue;
      L[i]=`${n}: ${v}`;return L.join("\n")}
    L.splice(end,0,`${k}: ${v}`);return L.join("\n")};
  const body=t=>{const L=t.split("\n"),end=fence(L);return end<0?t:L.slice(end+1).join("\n").replace(/^[-\n]+/,"")};
  const section=(t,h)=>{const L=t.split("\n");const st=L.findIndex(l=>l.trim()===h);if(st<0)return "";const o=[];
    for(let i=st+1;i<L.length;i++){if(L[i].startsWith("## "))break;o.push(L[i])}return o.join("\n").trim()};
  const title=(t,fb)=>{const L=t.split("\n");const h=L.findIndex(l=>l.startsWith("# "));if(h<0)return fb;
    for(let i=h+1;i<L.length;i++){const l=L[i].trim();if(l.startsWith("#"))break;if(l)return l}return fb};
  const slugOf=t=>t.normalize("NFD").replace(/\p{M}/gu,"").replace(/[^A-Za-z0-9]/g,"-").toLowerCase().split("-").filter(Boolean).slice(0,6).join("-");
  const safe=v=>/^[A-Za-z0-9_-]+$/.test(v);

  let f=parse(s);
  if(!Object.keys(f).length)fail("markdown has no frontmatter");
  const ids=(e.IDS||"").split("\n").filter(Boolean);
  let id;
  if(e.PARENT){
    if(!/^T-\d{3,}$/.test(e.PARENT)||!ids.includes(e.PARENT))fail(`parent must be an existing top-level task id like T-005, not ${e.PARENT}`);
    const p=e.PARENT+"-";const hi=ids.filter(i=>i.startsWith(p)).map(i=>/^\d+$/.test(i.slice(p.length))?+i.slice(p.length):0).reduce((a,b)=>Math.max(a,b),0);
    id=`${e.PARENT}-${String(hi+1).padStart(2,"0")}`;
  }else{
    const hi=ids.map(i=>{const m=/^T-(\d{3,})(?:-\d{2,})?$/.exec(i);return m?+m[1]:0}).reduce((a,b)=>Math.max(a,b),0);
    id=`T-${String(hi+1).padStart(3,"0")}`;
  }
  s=set(s,"id",id);
  const br=parse(s).branch||"",sl=br.indexOf("/");
  if(br&&sl>=0){const rest=br.slice(sl+1).replace(/^T-\d{3,}(-\d{2,})?-/,"");s=set(s,"branch",`${br.slice(0,sl+1)}${id}${rest?"-"+rest:""}`)}
  for(const [k,v] of [["runtime","default"],["depends_on","[]"],["parallel_group","null"],["attempt","0"],["max_attempts","3"],["plan_hash","null"],["owner","null"],["mr_url","null"]])
    if(!(k in parse(s)))s=set(s,k,v);
  if(!("created" in parse(s)))s=set(s,"created",e.TODAY);
  f=parse(s);

  if(!safe(e.REPO))fail("repo must be a key from repos.yml (letters, digits, - and _)");
  if(f.repo!==e.REPO)fail("repo in the frontmatter must match --repo");
  const miss=["id","repo","status","tier","archetype","complexity","runtime","depends_on","parallel_group","attempt","max_attempts","plan_hash","owner","mr_url","created"].filter(k=>!(k in f));
  if(miss.length)fail("missing key: "+miss.join(", "));
  const en=(k,vs)=>{if(!vs.includes(f[k]))fail(`${k} must be one of ${vs.join("|")}`)};
  en("archetype",["feature","bugfix","refactor","research","review","triage","ops"]);
  en("status",["draft","triaged","ready","claimed","in_progress","tests_ready","review","blocked","stalled","failed","done","closed"]);
  en("tier",["green","yellow","red"]);
  en("complexity",["low","medium","high"]);
  if(f.phase&&!["tests","implement"].includes(f.phase))fail("phase must be one of tests|implement, or absent");
  if(f.agent&&!["claude","codex"].includes(f.agent))fail("agent must be one of claude|codex, or absent");
  const stateOnly=f.archetype==="triage"||f.archetype==="ops";
  if(stateOnly?(f.branch||"").length>0:!(f.branch||"").length)fail(stateOnly?`${f.archetype} task must not have a branch`:"task must have a branch");
  if(stateOnly&&(f.base_branch||"").length)fail(`${f.archetype} task must not have a base_branch`);
  if(f.status!=="draft")fail("a new task may only be created as draft");
  if(f.archetype==="research"){
    const b=body(s);const m=/(?:^|`)\s*(test-filter|test|build|mutation)\b/m.exec(section(b,"## Acceptance"));
    if(m)fail(`\`archetype: research\` cannot satisfy this \`## Acceptance\`: \`${m[1]}\` is a toolset command that only passes by committing product-repo state (docs/design/toolset.md), and a research task is read-only towards the product repo (block-research, ADR-0016). Fold it into the dependent task that commits, or cut a separate committing task; do not switch archetype.`);
    const docs=section(b,"## Docs").trim().replace(/^[`.]+|[`.]+$/g,"").trim();
    if(docs.length&&docs.toLowerCase()!=="none"&&!section(b,"## Context").includes("architecture-docs"))
      fail("`archetype: research` cannot satisfy this `## Docs`: a research task may not write into the product repo (block-research, ADR-0016). The one carve-out is the architecture-docs handoff, and only when `## Context` carries `- skill: architecture-docs`; otherwise write `none` here.");
  }
  if(e.STATUS==="claimed"){s=set(s,"status","claimed");s=set(s,"owner",e.OWNER)}
  if(e.SLUG&&!(safe(e.SLUG)&&e.SLUG.length<=60))fail("slug: only letters, digits, - and _, at most 60 characters");
  const slug=e.SLUG||slugOf(title(body(s),id));
  process.stdout.write(id+"\n"+slug+"\n"+s);
})' < "$file") || exit 1

# E (2026-09-22, MR !412): the `# Goal` line becomes the MR title as written, and until now nothing looked at
# it before mr-open.sh did - after the human had approved the task and plan_hash pinned the body. The one rule
# lives in lib-tasks.sh; this shells out to it rather than restating the regex and the cap in the node
# validator above. A triage or research goal never becomes a title, so neither is held to it.
arch=$(sed -n 's/^archetype:[[:space:]]*//p' "$file" | head -n1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
case "$arch" in
  triage|research) ;;
  *)
    goal=$(awk '/^#+[[:space:]]*Goal[[:space:]]*$/ { f = 1; next } f && /^#/ { exit } f && NF { print; exit }' "$file")
    [ -n "$goal" ] || die "the draft has no '# Goal' line, and it is the MR title"
    reason=$(mr_title_check "$goal" "$repo") || die "the '# Goal' line cannot be an MR title: $reason; rewrite it in $file"
    ;;
esac

id=$(printf '%s\n' "$res" | sed -n 1p)
slug=$(printf '%s\n' "$res" | sed -n 2p)
rel="repos/$repo/tasks/$id${slug:+-$slug}.md"
[ ! -e "$state/$rel" ] || die "$rel already exists"

mkdir -p "$state/repos/$repo/tasks"
printf '%s\n' "$res" | sed '1,2d' > "$state/$rel"
state_commit "$state" "chore($id): new $status task" "$rel" || die "the new task could not be committed in $state"
}

state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die "the state lock could not be taken in $state; is it a git clone?" ;;
esac

try=0
while :; do
  sync_state
  assign_and_commit
  [ "$has_origin" = 1 ] || break
  sha=$(git -C "$state" rev-parse HEAD)
  git -C "$state" push -q >/dev/null 2>&1 && break
  git -C "$state" fetch -q >/dev/null 2>&1 || :
  git -C "$state" merge-base --is-ancestor "$sha" '@{u}' 2>/dev/null && break
  try=$((try + 1))
  [ "$try" -lt 3 ] || die "the push to the state remote failed 3 times; $rel is committed in $state but not pushed"
  [ "$(git -C "$state" rev-parse HEAD)" = "$sha" ] \
    || die "the push was refused and $state moved past $id's commit; $rel is committed there but not pushed, nothing was reset"
  git -C "$state" reset -q --keep HEAD~1
done
printf '{"id":"%s","file":"%s"}\n' "$id" "$rel"
