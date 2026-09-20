#!/bin/sh
# forge.sh — one entry point for READING issues and MRs from GitHub, GitLab and Gitea: it picks the tool
# (gh/glab/tea) from the URL shape, so the agent does not have to try them all. Write actions deliberately do not
# belong here — they differ enough between forges to turn the wrapper into a translator, and the skills describe them directly.
# ponytail: routing is by URL shape, same rule as in the dashboard (ForgeParsing.MergeRequestCommand):
# github.com → gh, a path with /-/ (GitLab's marker) → glab, /<owner>/<repo>/(issues|pulls)/<n> → tea (Gitea),
# anything else → glab. GitHub Enterprise would fall under glab; when it comes up, the host gets added here.
# `tea api <host> <path>` is a PSEUDO-command of the forge-guard wrapper (real tea has no api command):
# the guard curls the Gitea REST API with the stored token, so only the shapes it implements may be used here.
set -eu

usage() {
  echo "usage: forge.sh hosts | issue <url> [--assets <dir>] | mr <url>" >&2
  exit 2
}

# "Logged in to <host> …" is the only reliable signal — the exit code fails on any broken instance
logged_in() { "$1" auth status 2>&1 | sed -n 's/.*Logged in to \([^ ]*\).*/\1/p' | sort -u | tr '\n' ' '; }

hosts() {
  echo "glab: $(logged_in glab)"
  echo "gh: $(logged_in gh)"
  # tea has no `auth status`; `tea login list` prints a table with the instance URLs — reduce them to hostnames
  echo "tea: $(tea login list 2>/dev/null | grep -oE 'https?://[^ |"'"'"']+' | sed 's#https\?://##;s#/.*##' | sort -u | tr '\n' ' ')"
}

try() {
  if ! "$@"; then
    { echo "forge.sh: '$*' failed — signed-in instances:"; hosts; } >&2
    exit 3
  fi
}

# Downloads a GitHub attachment; a file without an extension gets one from the content-type, so it opens as an image.
fetch_github_asset() {
  dir=$1; u=$2
  name=${u##*/}; name=${name%%\?*}
  if ! ct=$(curl -fsSL -o "$dir/$name" -w '%{content_type}' "$u" 2>/dev/null); then
    rm -f "$dir/$name"
    echo "asset skipped: $u (download failed — the API does not hand out private GitHub attachments)" >&2
    return 0
  fi
  case "$name" in
    *.*) ;;
    *)
      case "$ct" in
        image/png*)  mv "$dir/$name" "$dir/$name.png";  name=$name.png ;;
        image/jpeg*) mv "$dir/$name" "$dir/$name.jpg";  name=$name.jpg ;;
        image/gif*)  mv "$dir/$name" "$dir/$name.gif";  name=$name.gif ;;
        image/svg*)  mv "$dir/$name" "$dir/$name.svg";  name=$name.svg ;;
        image/webp*) mv "$dir/$name" "$dir/$name.webp"; name=$name.webp ;;
      esac ;;
  esac
  echo "$dir/$name"
}

# Attachments from the issue output ($2) into a directory ($1). GitLab through the guarded `glab api` (GitLab >= 17.2,
# forge-guard endpoint #272), GitHub through curl on a signed URL (private repos do not work — skipped).
# One failed attachment is not fatal: whatever downloaded is printed as a local path.
download_assets() {
  dir=$1; src=$2; path=$3; host=$4
  mkdir -p "$dir"
  found=0
  if [ "$host" = "github.com" ]; then
    for a in $(grep -oE 'https://(github\.com/user-attachments/(assets|files)/[A-Za-z0-9./_-]+|[a-z-]*user-images\.githubusercontent\.com/[^)"\\[:space:]]+|objects\.githubusercontent\.com/[^)"\\[:space:]]+)' "$src" | sort -u); do
      found=1
      fetch_github_asset "$dir" "$a"
    done
  else
    proj=$(printf '%s' "$path" | sed 's#/#%2F#g')
    for a in $(grep -oE '(/-/project/[0-9]+)?/uploads/[a-f0-9]+/[^)"\\[:space:]]+' "$src" | sort -u); do
      found=1
      file=${a##*/}
      secret=$(printf '%s' "$a" | sed -n 's#.*/uploads/\([a-f0-9]*\)/.*#\1#p')
      case "$a" in
        /-/project/*) p=$(printf '%s' "$a" | sed -n 's#^/-/project/\([0-9]*\)/.*#\1#p') ;;
        *) p=$proj ;;
      esac
      # prefix from the secret: pasted screenshots on GitLab are all called image.png
      # (dest, not out — the caller holds out as a temp file with the issue output and a trap deletes it)
      dest="$dir/$(printf '%.8s' "$secret")-$file"
      if glab api --hostname "$host" "projects/$p/uploads/$secret/$file" > "$dest" 2>/dev/null; then
        echo "$dest"
      else
        rm -f "$dest"
        echo "asset skipped: $a (glab api failed — GitLab < 17.2, or missing permissions)" >&2
      fi
    done
  fi
  [ "$found" = 1 ] || echo "(no attachments)"
}

[ $# -ge 1 ] || usage
cmd=$1

case "$cmd" in
  hosts)
    hosts
    ;;
  issue|mr)
    [ $# -ge 2 ] || usage
    assets=""
    if [ "$cmd" = issue ] && [ $# -eq 4 ] && [ "$3" = "--assets" ]; then
      assets=$4
    elif [ $# -ne 2 ]; then
      usage
    fi
    host=$(printf '%s' "$2" | sed -n 's#^[a-zA-Z+]*://\([^/]*\)/.*#\1#p')
    [ -n "$host" ] || { echo "forge.sh: cannot parse URL: $2" >&2; exit 2; }
    # project and number from the URL: glab takes the host from the URL only for the main object, and the comments then
    # hit gitlab.com (401 on self-hosted). The only thing that keeps both on one instance is -R <host>/<project>.
    # Side effect: /-/work_items/<iid> works too, which is how GitLab 17 links issues.
    path=$(printf '%s' "$2" | sed -n 's#^[a-zA-Z+]*://[^/]*/\(.*\)/-/[a-z_]*/[0-9].*#\1#p')
    iid=$(printf '%s' "$2" | sed -n 's#.*/-/[a-z_]*/\([0-9][0-9]*\).*#\1#p')
    # Gitea shape: exactly /<owner>/<repo>/(issues|pulls)/<n> — an issue URL says issues, an MR URL says pulls
    case "$cmd" in issue) seg=issues ;; *) seg=pulls ;; esac
    gpath=$(printf '%s' "$2" | sed -n "s#^[a-zA-Z+]*://[^/]*/\([^/][^/]*/[^/][^/]*\)/$seg/[0-9].*#\1#p")
    gnum=$(printf '%s' "$2" | sed -n "s#^[a-zA-Z+]*://[^/]*/[^/][^/]*/[^/][^/]*/$seg/\([0-9][0-9]*\).*#\1#p")

    gitea=""
    out=$(mktemp)
    trap 'rm -f "$out"' EXIT

    if [ "$host" = "github.com" ]; then
      case "$cmd" in
        issue) try gh issue view "$2" --json number,title,body,labels,state,milestone,comments > "$out" ;;
        mr) try gh pr view "$2" --json number,title,body,state,isDraft,mergeable,headRefName,baseRefName,closingIssuesReferences,changedFiles,comments > "$out" ;;
      esac
    elif [ -n "$gpath" ] && [ -n "$gnum" ] && [ -z "$iid" ]; then
      gitea=1
      # the detail and the comments are two API calls; the comments always live under issues/<n>/comments — for pulls too
      case "$cmd" in
        issue) { try tea api "$host" "repos/$gpath/issues/$gnum"; echo; echo "--- comments ---"; try tea api "$host" "repos/$gpath/issues/$gnum/comments"; } > "$out" ;;
        mr) { try tea api "$host" "repos/$gpath/pulls/$gnum"; echo; echo "--- comments ---"; try tea api "$host" "repos/$gpath/issues/$gnum/comments"; } > "$out" ;;
      esac
    else
      [ -n "$path" ] && [ -n "$iid" ] \
        || { echo "forge.sh: cannot take the project and number from the URL: $2" >&2; exit 2; }
      # glab keeps the detail and the comments in two calls; make the separator visible in the output
      case "$cmd" in
        issue) { try glab issue view "$iid" -R "$host/$path" -F json; echo; echo "--- comments ---"; try glab issue view "$iid" -R "$host/$path" --comments; } > "$out" ;;
        mr) { try glab mr view "$iid" -R "$host/$path" -F json; echo; echo "--- comments ---"; try glab mr view "$iid" -R "$host/$path" --comments; } > "$out" ;;
      esac
    fi
    cat "$out"

    if [ -n "$assets" ]; then
      echo
      echo "--- assets ---"
      if [ -n "$gitea" ]; then
        # ponytail: the guard has no attachment endpoint yet; when it grows one (repos/…/issues/…/assets),
        # download here the way download_assets does for the other forges.
        echo "(gitea attachments not supported yet)"
        echo "forge.sh: gitea attachments are not downloaded — the forge-guard has no attachment endpoint yet" >&2
      else
        download_assets "$assets" "$out" "$path" "$host"
      fi
    fi
    ;;
  *)
    usage
    ;;
esac
