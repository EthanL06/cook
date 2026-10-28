#!/bin/bash
# Usage: cleanup.sh list [ref ...]
#        cleanup.sh run <machine>:<agent-id>:<ref> ...
# list: finds every cook build (an agent with a cook-step label) on each machine and prints one line per build:
#   target  - the PR is merged, or the ref is named on the command line
#   suggest - the PR is closed without a merge, or the agent has had no activity for COOK_STALE_DAYS days (default 7)
#   keep    - the PR is open, or there is no PR yet
#   skip    - the worktree has uncommitted or unpushed work. run never removes it.
#   Then one line per machine: cook builds, Paseo worktrees and free disk, "full" above COOK_MAX_BUILDS builds (default 8)
#   or below COOK_MIN_FREE_GB GB free (default 20).
# run: for each build, checks again for unsaved work, then archives the agent, stops the processes that run in its worktree,
#   removes the worktree and its local branch, and deletes its event log. It never touches the issue, the PR or the remote branch.
# Exit codes: 0 done, 1 bad arguments, 2 one or more builds were skipped or a step failed.
set -u
. "$(dirname "$0")/lib.sh"
mode=${1:-}; shift 2>/dev/null
case "$mode" in list|run) ;; *) mode= ;; esac
[ -n "$mode" ] || { echo "usage: cleanup.sh list [ref ...] | cleanup.sh run <machine>:<agent-id>:<ref> ..." >&2; exit 1; }
[ "$mode" = list ] || [ "$#" -gt 0 ] || { echo "run needs at least one <machine>:<agent-id>:<ref>" >&2; exit 1; }

stale_days=${COOK_STALE_DAYS:-7}
max_builds=${COOK_MAX_BUILDS:-8}
min_free_gb=${COOK_MIN_FREE_GB:-20}

PROBE='d=$1; case $d in "~"/*) d=$HOME/${d#"~/"} ;; esac
[ -d "$d" ] || { echo exists=0; exit 0; }
echo exists=1
echo path=$d
echo branch=$(git -C "$d" branch --show-current)
echo head=$(git -C "$d" rev-parse HEAD)
echo repo=$(dirname "$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)")
echo origin=$(git -C "$d" remote get-url origin 2>/dev/null)
echo dirty=$(git -C "$d" status --porcelain | wc -l | tr -d " ")
echo unpushed=$(git -C "$d" rev-list --count HEAD --not --remotes=origin)'

MACHINE='echo worktrees=$(ls -d "$HOME"/.paseo/worktrees/*/*/ 2>/dev/null | wc -l | tr -d " ")
echo free_gb=$(df -Pk "$HOME" | awk "NR==2 { print int(\$4 / 1048576) }")'

# Finds every process whose working directory is inside the worktree: /proc on Linux, lsof on macOS.
STOP='d=$1; case $d in "~"/*) d=$HOME/${d#"~/"} ;; esac
pids=""
if [ -d /proc/self ]; then
  for p in /proc/[0-9]*; do c=$(readlink "$p/cwd" 2>/dev/null) || continue
    case $c in "$d"|"$d"/*) pids="$pids ${p#/proc/}" ;; esac; done
else
  pids=$(lsof -a -d cwd -F pn 2>/dev/null | awk -v d="$d" "/^p/ { p = substr(\$0, 2) } /^n/ { n = substr(\$0, 2); if (n == d || index(n, d \"/\") == 1) print p }")
fi
pids=$(echo $pids)
[ -n "$pids" ] && kill $pids 2>/dev/null
echo stopped=${pids:-none}'

REMOVE='d=$1 repo=$2 branch=$3 id=$4; case $d in "~"/*) d=$HOME/${d#"~/"} ;; esac
if [ -d "$d" ]; then git -C "$repo" worktree remove "$d" || exit 3; fi
git -C "$repo" worktree prune
if [ -n "$branch" ] && git -C "$repo" show-ref -q --verify "refs/heads/$branch"; then git -C "$repo" branch -D "$branch" >/dev/null || exit 4; fi
rm -f "$HOME/.local/state/cook/events/$id.log"
echo removed=1'

pr_word() { if [ "$1" = none ]; then echo "no PR"; else echo "PR $(tr "[:upper:]" "[:lower:]" <<<"$1")"; fi; }

# Prints "<state> <head sha> <url>" for the newest PR of the branch, or "none - -".
pr_of() {
  local slug branch=$2
  slug=$(sed -E 's#^.*github\.com[:/]##; s#\.git$##' <<<"$1")
  [ -n "$slug" ] && [ -n "$branch" ] || { echo "none - -"; return; }
  gh pr list -R "$slug" --head "$branch" --state all --limit 1 --json state,headRefOid,url \
    --jq '.[0] // empty | "\(.state) \(.headRefOid) \(.url)"' 2>/dev/null | grep . || echo "none - -"
}

# A commit counts as saved when it is on origin, or when it is the head of the PR (GitHub can delete the branch on merge).
unsaved() {
  local dirty=$1 unpushed=$2 head=$3 pr_head=$4
  [ "${dirty:-0}" -gt 0 ] && { echo "$dirty uncommitted file(s)"; return; }
  [ "${unpushed:-0}" -gt 0 ] && [ "$head" != "$pr_head" ] && { echo "$unpushed unpushed commit(s)"; return; }
  return 1
}

# Days since the build's last event, from its event log.
idle_days() {
  local last
  last=$(cook_events "$1" "$2" | tail -n 1 | awk '{ print $3 }')
  [ -n "$last" ] || { echo 0; return; }
  python3 -I -c 'import sys, datetime as d
t = d.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print((d.datetime.now(d.timezone.utc) - t).days)' "$last" 2>/dev/null || echo 0
}

if [ "$mode" = list ]; then
  named=" $* "
  printf '%-8s %-12s %-16s %-7s %-34s %s\n' VERDICT REF MACHINE PR REASON BUILD
  summary=""
  for m in $(cook_machines); do
    builds=0
    while IFS=$'\t' read -r -u 3 id _ ref cwd; do
      builds=$((builds + 1))
      p=$(on "$m" "$PROBE" "$cwd")
      read -r pr_state pr_head pr_url <<<"$(pr_of "$(kv origin "$p")" "$(kv branch "$p")")"
      days=$(idle_days "$m" "$id")
      why=""
      [ "$(kv exists "$p")" = 1 ] && why=$(unsaved "$(kv dirty "$p")" "$(kv unpushed "$p")" "$(kv head "$p")" "$pr_head")
      if [ -n "$why" ]; then verdict=skip reason=$why
      elif [ "$pr_state" = MERGED ]; then verdict=target reason="PR merged"
      elif [[ $named == *" $ref "* || $named == *" ${ref#\#} "* ]]; then verdict=target reason="named, $(pr_word "$pr_state")"
      elif [ "$pr_state" = CLOSED ]; then verdict=suggest reason="PR closed without a merge"
      elif [ "$days" -ge "$stale_days" ]; then verdict=suggest reason="no activity for $days days"
      else verdict=keep reason=$(pr_word "$pr_state")
      fi
      [ "$(kv exists "$p")" = 1 ] || reason="$reason, worktree is gone"
      printf '%-8s %-12s %-16s %-7s %-34s %s\n' "$verdict" "$ref" "$m" "$(basename "$pr_url")" "$reason" "$m:$id:$ref"
    done 3< <(cook_builds "$m")
    mm=$(on "$m" "$MACHINE")
    w=$(kv worktrees "$mm"); f=$(kv free_gb "$mm")
    full=""; { [ "$builds" -gt "$max_builds" ] || [ "${f:-999}" -lt "$min_free_gb" ]; } && full="  full"
    summary+=$(printf '\nMACHINE  %-16s %s cook builds, %s Paseo worktrees, %s GB free%s' "$m" "$builds" "${w:-?}" "${f:-?}" "$full")
  done
  echo "$summary" | sed '/^$/d'
  exit 0
fi

rc=0
for b in "$@"; do
  IFS=: read -r m id ref <<<"$b"
  [ -n "$m" ] && [ -n "$id" ] && [ -n "$ref" ] || { echo "$b: bad build string" >&2; rc=2; continue; }
  cwd=$(pas "$m" inspect "$id" --json 2>/dev/null | jq -r '.Cwd // .cwd // empty')
  [ -n "$cwd" ] || { echo "$ref $m: skipped, agent $id not found"; rc=2; continue; }
  p=$(on "$m" "$PROBE" "$cwd")
  if [ "$(kv exists "$p")" = 1 ]; then
    read -r _ pr_head _ <<<"$(pr_of "$(kv origin "$p")" "$(kv branch "$p")")"
    if why=$(unsaved "$(kv dirty "$p")" "$(kv unpushed "$p")" "$(kv head "$p")" "$pr_head"); then
      echo "$ref $m: skipped, $why in $(kv path "$p")"; rc=2; continue
    fi
  fi
  pas "$m" archive --force "$id" >/dev/null 2>&1 || { echo "$ref $m: failed to archive agent $id"; rc=2; continue; }
  stopped=$(kv stopped "$(on "$m" "$STOP" "$cwd")")
  pas "$m" worktree archive "$(kv branch "$p")" --cwd "$(kv repo "$p")" >/dev/null 2>&1
  r=$(on "$m" "$REMOVE" "$cwd" "$(kv repo "$p")" "$(kv branch "$p")" "$id" 2>&1)
  if [ "$(kv removed "$r")" != 1 ]; then echo "$ref $m: agent archived, but the worktree was not removed: $(tail -n 1 <<<"$r")"; rc=2; continue; fi
  rm -f "${COOK_WATCH_DIR:-${TMPDIR:-/tmp}/cook-watch}/$id"
  echo "$ref $m: cleaned up. Agent archived, processes stopped: ${stopped:-none}, worktree and branch $(kv branch "$p") removed, event log deleted."
done
exit "$rc"
