#!/bin/sh
# Writes a new task straight into a state clone, which in the standalone posture (ADR-0050) is how every task
# comes into being: the id, the slug from the title, the frontmatter validated by the node check below, then one
# local commit, all under the state lock of lib-tasks.sh, so two sessions on one clone never hand out one id.
# The id: a repo with an `alias:` in repos.yml gets T-<ALIAS>-<n>, one more than the highest n of that alias over
# the live and the archived tasks; a repo without one keeps the legacy counter, one more than the highest T-<n>
# taken anywhere; a block (--parent) is its parent plus -NN. Nothing talks to the remote: no pull before and no
# push after, state-push.sh publishes the commit in the background and never under the lock, so there is no
# refused push to undo and no reset of any kind.
# The frontmatter carries `request:` (R-YYYYMMDD-n or null), `priority:` (P0 to P3, P2 when a parent leaves it
# out) and `issue:` (an http(s) url or null); a block copies all three from its parent over its own.
#
#   task-new.sh --repo <key> [--parent <parent id>] [--slug <slug>] [--status claimed --owner <owner>] [--state <dir>] --file <markdown>
#
# cwd = the state clone unless --state. Prints {"id":…,"file":…}; a refusal is exit 1 with the reason on stderr
# and nothing written. `--status claimed --owner` is for a block a session cuts for itself: it is born claimed
# by that session.
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
[ -d "$state/.git" ] || die "$state is not a state clone, run from one or pass --state <dir>"

# state_commit is shared with task-approve.sh and state-report.sh
. "$(dirname -- "$0")/lib-tasks.sh"
case "$status" in
  draft) ;;
  claimed) [ -n "$owner" ] || die "--status claimed needs --owner <owner>" ;;
  *) die "--status may only be claimed (with --owner); a new task is draft otherwise" ;;
esac
alias=$(repo_alias "$repo") \
  || die "the alias '$(yml_field "$repo" alias)' of $repo in repos.yml is not 2 to 4 uppercase letters, fix it there"

# a block write is held to the architect verdict of the plan it names, before anything is locked or
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

assign_and_commit() {
# every id already taken, across every repo, live and archived: the next id is one more than the highest of its
# kind. One `id:` per file, the first one: a task body may quote an `id:` line of its own (a frontmatter example,
# a diff), and over the concatenated files that quote would count as a taken id and skip a number.
ids=$(task_files --all | awk '{
  f = $0
  while ((getline l < f) > 0) if (l ~ /^id:/) { sub(/^id:[ \t]*/, "", l); sub(/[ \t]*#.*/, "", l); print l; break }
  close(f) }')

# a block takes request, priority and issue from its parent, read here under the lock so a priority change the
# lock serializes is not missed
preq='' ppri='' piss=''
if [ -n "$parent" ]; then
  pv=$(task_fields "$(task_of "$parent")" request priority issue)
  preq=$(printf '%s\n' "$pv" | sed -n 1p)
  ppri=$(printf '%s\n' "$pv" | sed -n 2p)
  piss=$(printf '%s\n' "$pv" | sed -n 3p)
fi

# ponytail: node is already a hard dependency of every session (policy-guard.sh); one process computes the id,
# inserts it into the branch, fills the bookkeeping defaults, validates and slugs. stdout = id, slug, markdown.
res=$(IDS=$ids REPO=$repo ALIAS=$alias PARENT=$parent PREQ=$preq PPRI=$ppri PISS=$piss SLUG=$slug STATUS=$status \
  OWNER=$owner TODAY=$(date +%F) node -e '
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
    if(!/^T-(?:[A-Z]{2,4}-\d+|\d{3,})$/.test(e.PARENT)||!ids.includes(e.PARENT))fail(`parent must be an existing top-level task id like T-005 or T-ECS-5, not ${e.PARENT}`);
    const p=e.PARENT+"-";const hi=ids.filter(i=>i.startsWith(p)).map(i=>/^\d+$/.test(i.slice(p.length))?+i.slice(p.length):0).reduce((a,b)=>Math.max(a,b),0);
    id=`${e.PARENT}-${String(hi+1).padStart(2,"0")}`;
  }else if(e.ALIAS){
    const re=new RegExp(`^T-${e.ALIAS}-(\\d+)(?:-\\d+)?$`);
    const hi=ids.map(i=>{const m=re.exec(i);return m?+m[1]:0}).reduce((a,b)=>Math.max(a,b),0);
    id=`T-${e.ALIAS}-${hi+1}`;
  }else{
    const hi=ids.map(i=>{const m=/^T-(\d{3,})(?:-\d{2,})?$/.exec(i);return m?+m[1]:0}).reduce((a,b)=>Math.max(a,b),0);
    id=`T-${String(hi+1).padStart(3,"0")}`;
  }
  s=set(s,"id",id);
  const br=parse(s).branch||"",sl=br.indexOf("/");
  if(br&&sl>=0){const rest=br.slice(sl+1).replace(/^(?:T-(?:[A-Z]{2,4}-\d+|\d{3,})(-\d{2,})?|<new-id>)(?:-|$)/,"");s=set(s,"branch",`${br.slice(0,sl+1)}${id}${rest?"-"+rest:""}`)}
  for(const [k,v] of [["depends_on","[]"],["attempt","0"],["plan_hash","null"],["owner","null"],["mr_url","null"],["request","null"],["issue","null"]])
    if(!(k in parse(s)))s=set(s,k,v);
  if(!parse(s).priority)s=set(s,"priority","P2");
  if(e.PARENT){s=set(s,"request",e.PREQ||"null");s=set(s,"priority",e.PPRI&&e.PPRI!=="null"?e.PPRI:"P2");s=set(s,"issue",e.PISS||"null")}
  if(!("created" in parse(s)))s=set(s,"created",e.TODAY);
  f=parse(s);

  if(!safe(e.REPO))fail("repo must be a key from repos.yml (letters, digits, - and _)");
  if(f.repo!==e.REPO)fail("repo in the frontmatter must match --repo");
  const miss=["id","repo","status","tier","archetype","complexity","depends_on","attempt","plan_hash","owner","mr_url","created"].filter(k=>!(k in f));
  if(miss.length)fail("missing key: "+miss.join(", "));
  const en=(k,vs)=>{if(!vs.includes(f[k]))fail(`${k} must be one of ${vs.join("|")}`)};
  en("archetype",["feature","bugfix","refactor","research","review","triage","ops"]);
  en("status",["draft","triaged","ready","claimed","in_progress","tests_ready","review","blocked","failed","done","closed"]);
  en("tier",["green","yellow","red"]);
  en("complexity",["low","medium","high"]);
  en("priority",["P0","P1","P2","P3"]);
  if(f.request&&!/^R-\d{8}-\d+$/.test(f.request))fail("request must be R-YYYYMMDD-n or null");
  if(f.issue&&!/^https?:\/\/\S+$/.test(f.issue))fail("issue must be an http(s) url or null");
  if(f.phase&&!["tests","implement"].includes(f.phase))fail("phase must be one of tests|implement, or absent");
  if(f.agent&&!["claude","codex"].includes(f.agent))fail("agent must be one of claude|codex, or absent");
  const stateOnly=f.archetype==="triage"||f.archetype==="ops";
  if(stateOnly?(f.branch||"").length>0:!(f.branch||"").length)fail(stateOnly?`${f.archetype} task must not have a branch`:"task must have a branch");
  if(stateOnly&&(f.base_branch||"").length)fail(`${f.archetype} task must not have a base_branch`);
  if(f.status!=="draft")fail("a new task may only be created as draft");
  if(f.archetype==="research"){
    const b=body(s);const m=/(?:^|`)\s*(test-filter|test|build|mutation)\b/m.exec(section(b,"## Acceptance"));
    if(m)fail(`\`archetype: research\` cannot satisfy this \`## Acceptance\`: \`${m[1]}\` is a toolset command that only passes by committing product-repo state, and a research task is read-only towards the product repo (block-research, ADR-0016). Fold it into the dependent task that commits, or cut a separate committing task; do not switch archetype.`);
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

# T-248: the state clone is one working tree shared by every session on the machine. The id, the write and the
# commit run under the one lock every state writer takes, so two runs cannot hand out one id; the commit names
# only this task's file, so another session's edit, staged or not, stays where it is.
state_lock "$state" && lrc=0 || lrc=$?
case "$lrc" in
  0) trap state_unlock EXIT ;;
  1) die "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
  *) die "the state lock could not be taken in $state; is it a git clone?" ;;
esac

assign_and_commit
printf '{"id":"%s","file":"%s"}\n' "$id" "$rel"
