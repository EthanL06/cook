#!/bin/bash
# Usage: resume.sh
#        resume.sh <ref> [--dirty-ok] [--new-worktree] [--dry-run] [-- <paseo run flags>]
# Run by the hub for /cook resume. It reads the run state that report.sh saves on each machine.
# No ref: lists the builds that are not done, with their step, agent and worktree.
# With a ref (or a run key, or the start of an agent ID): checks the worktree, the branch and the agent, then:
#   - the agent is idle in Paseo: sends it the resume brief (templates/resume.md).
#   - the agent is gone (archived, stopped with an error, or not known to Paseo): starts a new agent in the same
#     worktree with the brief. Its provider, model and mode are the old agent's, unless you give paseo run flags.
#   The brief names the step to continue from, the approved spec copy and the last verify receipt.
# It changes nothing and stops when:
#   - the worktree is gone (exit 4). --new-worktree checks out the branch in a new worktree, if the branch has the last commit.
#   - the worktree is on another branch, or its head does not have the last saved commit (exit 4).
#   - the worktree has uncommitted changes (exit 5). Tell the user, and use --dirty-ok only after they agree.
#   - the agent is running, or another cook agent works in the worktree (exit 6).
# --dry-run prints the checks and the brief, and starts or sends nothing.
# Exit codes: 0 resumed or listed, 1 bad arguments, 2 no run state matches, 3 the machine does not answer,
#   4 the worktree or branch is not safe to use, 5 uncommitted changes, 6 an agent is at work, 7 paseo failed.
set -u
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
RUN="python3 -I $COOK_LIB_DIR/run.py"

want="" dirty_ok=0 new_wt=0 dry=0 extra=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dirty-ok) dirty_ok=1 ;;
    --new-worktree) new_wt=1 ;;
    --dry-run) dry=1 ;;
    --) shift; extra=("$@"); break ;;
    -*) echo "usage: resume.sh [<ref> [--dirty-ok] [--new-worktree] [--dry-run] [-- <paseo run flags>]]" >&2; exit 1 ;;
    *) [ -z "$want" ] || { echo "only one ref" >&2; exit 1; }; want=$1 ;;
  esac
  shift
done

PROBE='d=$1 repo=$2 b=$3 sha=$4; case $d in "~"/*) d=$HOME/${d#"~/"} ;; esac; case $repo in "~"/*) repo=$HOME/${repo#"~/"} ;; esac
echo home=$HOME
if [ -d "$d" ] && git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
  echo exists=1
  echo path=$d
  echo branch=$(git -C "$d" branch --show-current)
  echo head=$(git -C "$d" rev-parse HEAD)
  echo dirty=$(git -C "$d" status --porcelain | wc -l | tr -d " ")
  echo files=$(git -C "$d" status --porcelain | head -n 10 | cut -c4- | paste -sd , -)
  [ -z "$sha" ] || git -C "$d" merge-base --is-ancestor "$sha" HEAD 2>/dev/null && echo has_sha=1
else
  echo exists=0
fi
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo repo=0; exit 0; }
echo repo=1
git -C "$repo" fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" 2>/dev/null
git -C "$repo" show-ref -q --verify "refs/heads/$b" && echo local_branch=1
for r in "refs/heads/$b" "refs/remotes/origin/$b"; do
  git -C "$repo" merge-base --is-ancestor "$sha" "$r" 2>/dev/null && { echo branch_has_sha=1; break; }
done
git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null && echo sha_known=1
echo in_use=$(git -C "$repo" worktree list --porcelain | awk -v want="branch refs/heads/$b" "/^worktree /{ w = substr(\$0, 10) } \$0 == want { print w }")'

age() { python3 -I -c 'import sys, datetime as d
t = d.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")); s = int((d.datetime.now(d.timezone.utc) - t).total_seconds())
print(f"{s // 60}m" if s < 3600 else f"{s // 3600}h" if s < 172800 else f"{s // 86400}d")' "$1" 2>/dev/null || echo "?"; }

# Prints "<status> <archived> <provider> <model> <mode>" for an agent, or "gone".
agent_info() {
  pas "$1" inspect "$2" --json 2>/dev/null | jq -r '"\(.Status // .status // "unknown") \(.Archived // false) \(.Provider // "-") \(.Model // "-") \(.Mode // "-")"' 2>/dev/null | grep . || echo gone
}
alive_word() {
  case "$1" in
    gone*|*" true "*) echo gone ;;
    idle*) echo idle ;;
    running*|initializing*) echo running ;;
    *) echo "gone (${1%% *})" ;;
  esac
}

gather() {
  local m
  for m in $(cook_machines); do
    if ! cook_up "$m"; then echo "DOWN	$m"; continue; fi
    cook_runs "$m" | sed "s/^/$m	/"
  done
}
all=$(gather)

if [ -z "$want" ]; then
  printf '%-12s %-12s %-14s %-10s %-24s %-6s %s\n' REF MACHINE STEP AGENT WORKTREE AGE KEY
  done_n=0
  while IFS=$'\t' read -r m js; do
    [ -n "$m" ] || continue
    [ "$m" = DOWN ] && { echo "MACHINE $js does not answer: its builds are not listed."; continue; }
    j() { jq -r "$1 // empty" <<<"$js"; }
    [ "$(j .step)" = ready ] && { done_n=$((done_n + 1)); continue; }
    p=$(on "$m" "$PROBE" "$(j .cwd)" "$(j .repo)" "$(j .branch)" "$(j .head)" 2>/dev/null)
    wt="gone"
    if [ "$(kv exists "$p")" = 1 ]; then
      wt="clean"
      [ "$(kv dirty "$p")" -gt 0 ] && wt="$(kv dirty "$p") uncommitted file(s)"
    fi
    step=$(j .step); [ "$step" = blocked ] && step="blocked:$(j .resume_step)"
    printf '%-12s %-12s %-14s %-10s %-24s %-6s %s\n' "$(j .ref)" "$m" "$step" "$(alive_word "$(agent_info "$m" "$(j .agent_id)")")" \
      "$wt" "$(age "$(j .updated)")" "$(j .key)"
  done <<<"$all"
  [ "$done_n" -gt 0 ] && echo "$done_n done build(s) not shown. /cook cleanup removes them."
  exit 0
fi

picked=$($RUN pick "$want" <<<"$(grep -v '^DOWN	' <<<"$all")") || {
  rc=$?
  grep '^DOWN	' <<<"$all" | cut -f2 | sed 's/^/not checked, it does not answer: /' >&2
  exit "$rc"
}
m=${picked%%$'\t'*}
js=${picked#*$'\t'}
j() { jq -r "$1 // empty" <<<"$js"; }
ref=$(j .ref) id=$(j .agent_id) cwd=$(j .cwd) repo=$(j .repo) branch=$(j .branch) sha=$(j .head)
[ "$(j .step)" = ready ] && { echo "$ref is done: its PR is ready ($(j .pr)). Nothing to resume. Send review fixes to the agent in Paseo."; exit 0; }

p=$(on "$m" "$PROBE" "$cwd" "$repo" "$branch" "$sha" 2>/dev/null)
[ -n "$(kv home "$p")" ] || { echo "$m does not answer: cannot check $ref." >&2; exit 3; }
short=$(cut -c1-7 <<<"$sha")

if [ "$(kv exists "$p")" != 1 ]; then
  if [ "$(kv repo "$p")" != 1 ]; then
    echo "the worktree $cwd and the checkout $repo are gone on $m. Nothing is changed." >&2; exit 4
  fi
  if [ "$(kv branch_has_sha "$p")" != 1 ]; then
    hint="The branch $branch is gone or does not have it."
    [ "$(kv sha_known "$p")" = 1 ] && hint="$hint The commit is still in $repo: git -C $repo branch $branch-saved $short"
    echo "the worktree $cwd is gone, and the last saved commit $short is on no branch. $hint" >&2; exit 4
  fi
  if [ -n "$(kv in_use "$p")" ]; then
    echo "the worktree $cwd is gone, but $branch is checked out in $(kv in_use "$p"). Resume from there by hand." >&2; exit 4
  fi
  if [ "$new_wt" != 1 ]; then
    echo "the worktree $cwd is gone. The branch $branch has the last saved commit $short. Run again with --new-worktree to check it out in a new worktree." >&2
    exit 4
  fi
elif [ "$(kv branch "$p")" != "$branch" ]; then
  echo "the worktree $cwd is on branch $(kv branch "$p"), not $branch. Nothing is changed." >&2; exit 4
elif [ -n "$sha" ] && [ "$(kv has_sha "$p")" != 1 ]; then
  echo "the head of $cwd ($(cut -c1-7 <<<"$(kv head "$p")")) does not have the last saved commit $short. Commits may be lost: check git reflog in $cwd. Nothing is changed." >&2
  exit 4
elif [ "$(kv dirty "$p")" -gt 0 ] && [ "$dirty_ok" != 1 ]; then
  echo "the worktree $cwd has $(kv dirty "$p") uncommitted file(s): $(kv files "$p"). Tell the user. If they agree, run again with --dirty-ok: the agent keeps the changes." >&2
  exit 5
fi

info=$(agent_info "$m" "$id")
alive=$(alive_word "$info")
wt_path=$(kv path "$p")
home=$(kv home "$p")
others=$(cook_builds "$m" | awk -F'\t' -v id="$id" -v home="$home" -v d="$wt_path" '{ c = $4; sub(/^~/, home, c) } $1 != id && d != "" && c == d { print $1 }')
if [ "$alive" = running ]; then
  echo "agent $id of $ref is running on $m: it is still at work. Watch it with /cook-status $ref, or stop it in Paseo first." >&2; exit 6
fi
if [ -n "$others" ]; then
  echo "another cook agent works in $wt_path on $m: $others. Nothing is changed." >&2; exit 6
fi

brief=$(mktemp "${TMPDIR:-/tmp}/cook-resume.XXXXXX")
$RUN brief --head "$(kv head "$p")" --dirty "$(kv dirty "$p")" <<<"$js" >"$brief"
step=$(sed -n 's/^Continue at: //p' "$brief")
label=$step; [ "$label" = pr ] && label=verify

action=send
[ "$alive" = idle ] && [ "$(kv exists "$p")" = 1 ] || action=start
if [ "$dry" = 1 ]; then
  printf 'machine=%s\nagent=%s (%s)\naction=%s\nstep=%s\nworktree=%s\n---\n' "$m" "$id" "$alive" "$action" "$step" "${wt_path:-new, from $branch}"
  cat "$brief"
  exit 0
fi

if [ "$action" = send ]; then
  pas "$m" send --no-wait "$id" --prompt-file "$brief" >/dev/null 2>"$brief.err" || { echo "paseo send failed on $m: $(tail -n 1 "$brief.err")" >&2; exit 7; }
  pas "$m" agent update "$id" --label "cook-step=$label" >/dev/null 2>&1
  printf 'resumed=sent\nbuild=%s:%s:%s\nstep=%s\nbrief=%s\n' "$m" "$id" "$ref" "$step" "$brief"
  exit 0
fi

flags=(${extra[@]+"${extra[@]}"})
if [ "${#flags[@]}" = 0 ] && [ "$info" != gone ]; then
  read -r _ _ provider model mode <<<"$info"
  [ "$provider" != - ] && flags+=(--provider "$provider")
  [ "$model" != - ] && flags+=(--model "$model")
  [ "$mode" != - ] && flags+=(--mode "$mode")
fi
args=(run --no-wait -q --title "$ref: $(j .title)" --label "cook=$ref" --label "cook-step=$label")
if [ "$(kv exists "$p")" = 1 ]; then
  args+=(--cwd "$wt_path")
else
  args+=(--cwd "$repo" --new-workspace worktree --worktree-mode checkout-branch --branch "$branch")
fi
args+=(${flags[@]+"${flags[@]}"} "$(cat "$brief")")
if ! res=$(pas "$m" "${args[@]}" 2>&1); then
  echo "paseo run failed on $m: $(tail -n 1 <<<"$res")" >&2
  exit 7
fi
new=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27,}|^[0-9a-f]{7,}$' <<<"$res" | head -n 1)
[ -n "$new" ] || { echo "paseo run on $m printed no agent ID: $(tail -n 1 <<<"$res")" >&2; exit 7; }
# The old agent keeps its history in Paseo, but leaves the cook step labels, so status and watch show only the new one.
[ "$info" != gone ] && pas "$m" agent update "$id" --label "cook-step=resumed" >/dev/null 2>&1
printf 'resumed=started\nbuild=%s:%s:%s\nreplaces=%s\nstep=%s\nbrief=%s\n' "$m" "$new" "$ref" "$id" "$step" "$brief"
