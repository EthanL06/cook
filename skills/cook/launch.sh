#!/bin/bash
# Usage: launch.sh --machine <m> --repo <checkout> --ref <ref> --title <title> --branch <branch> --base <base> --brief <file>
#                  [-- <more paseo run flags, for example --provider claude --mode bypassPermissions>]
# Run by the hub (intake step 3). Starts the build agent in a new Paseo worktree on <m> ("local" or a Tailscale name).
# <checkout> is the repo's checkout on that machine. Before it starts the agent, it checks:
#   - the machine answers over SSH and its Paseo daemon answers,
#   - the base branch is on origin,
#   - the branch: new (branch off origin/<base>), on origin (check it out), or only local (check it out).
#     A local branch that is behind origin is moved forward to origin first. A local branch with more commits than
#     origin is used as it is. It never moves a branch back.
#     It stops when the branch is checked out in another worktree (a build may use it) or when local and origin differ.
# Prints key=value lines: build=<m>:<agent-id>:<ref>, agent, branch, mode (new, origin or local), note.
# Exit codes: 0 started, 1 bad arguments, 3 the machine or its Paseo daemon does not answer,
#   4 no checkout or no base branch on origin, 5 the branch is in use or differs from origin, 6 paseo run failed.
set -u
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

m="" repo="" ref="" title="" branch="" base="" brief="" extra=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --machine) m=${2:-} ;;
    --repo) repo=${2:-} ;;
    --ref) ref=${2:-} ;;
    --title) title=${2:-} ;;
    --branch) branch=${2:-} ;;
    --base) base=${2:-} ;;
    --brief) brief=${2:-} ;;
    --) shift; extra=("$@"); break ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift 2 || { echo "$1 needs a value" >&2; exit 1; }
done
for v in m repo ref title branch base brief; do
  [ -n "${!v}" ] || { echo "usage: launch.sh --machine <m> --repo <checkout> --ref <ref> --title <title> --branch <branch> --base <base> --brief <file> [-- <paseo run flags>]" >&2; exit 1; }
done
[ -f "$brief" ] || { echo "no brief file: $brief" >&2; exit 1; }

PROBE='R=$1 base=$2 b=$3; case $R in "~"/*) R=$HOME/${R#"~/"} ;; esac
git -C "$R" rev-parse --git-dir >/dev/null 2>&1 || { echo repo=0; exit 0; }
echo repo=1
echo path=$R
if git -C "$R" fetch -q origin "$base" 2>/dev/null; then echo base=1; else echo base=0; exit 0; fi
git -C "$R" ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; r=$?
case $r in
  0) git -C "$R" fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" && echo origin=1 && echo origin_sha=$(git -C "$R" rev-parse "refs/remotes/origin/$b") ;;
  2) echo origin=0 ;;
  *) echo origin=error ;;
esac
if git -C "$R" show-ref -q --verify "refs/heads/$b"; then
  echo local=1
  echo local_sha=$(git -C "$R" rev-parse "refs/heads/$b")
  echo ahead=$(git -C "$R" rev-list --count "origin/$base..refs/heads/$b")
  git -C "$R" merge-base --is-ancestor "refs/remotes/origin/$b" "refs/heads/$b" 2>/dev/null && echo has_origin=1
else
  echo local=0
fi
echo worktree=$(git -C "$R" worktree list --porcelain | awk -v want="branch refs/heads/$b" "/^worktree /{ w = substr(\$0, 10) } \$0 == want { print w }")'

# Moves the local branch forward to origin. update-ref with the old value fails if the branch moved since the probe.
FORWARD='R=$1 b=$2 old=$3 new=$4; case $R in "~"/*) R=$HOME/${R#"~/"} ;; esac
git -C "$R" merge-base --is-ancestor "$old" "$new" && git -C "$R" update-ref "refs/heads/$b" "$new" "$old" && echo forwarded=1'

if [ "$m" != local ] && ! on "$m" 'echo ok' >/dev/null 2>&1; then
  echo "cannot reach $m over SSH. Check that it is on and in Tailscale (tailscale status), or pick another machine." >&2
  exit 3
fi
if ! perr=$(pas "$m" ls -q 2>&1 >/dev/null); then
  echo "the Paseo daemon on $m does not answer: $(tail -n 1 <<<"$perr"). Open the Paseo app there, or run: paseo" >&2
  exit 3
fi

p=$(on "$m" "$PROBE" "$repo" "$base" "$branch" 2>/dev/null)
[ "$(kv repo "$p")" = 1 ] || { echo "no git checkout at $repo on $m" >&2; exit 4; }
[ "$(kv base "$p")" = 1 ] || { echo "the base branch $base is not on origin (git fetch origin $base failed in $repo on $m)" >&2; exit 4; }
[ "$(kv origin "$p")" = error ] && { echo "cannot read the branches on origin from $repo on $m" >&2; exit 4; }

wt=$(kv worktree "$p")
local_sha=$(kv local_sha "$p") origin_sha=$(kv origin_sha "$p")
if [ -n "$wt" ]; then
  echo "branch $branch is checked out in $wt on $m. A build may use it: resume it with /cook resume $ref, or pick another branch." >&2
  exit 5
fi
note=""
if [ "$(kv local "$p")" = 1 ] && [ "$(kv origin "$p")" = 1 ] && [ "$local_sha" != "$origin_sha" ]; then
  if [ "$(kv has_origin "$p")" = 1 ]; then
    note="The local branch has commits that are not on origin yet."
  elif [ "$(kv forwarded "$(on "$m" "$FORWARD" "$repo" "$branch" "$local_sha" "$origin_sha")")" = 1 ]; then
    note="Moved the local branch forward to origin ($(cut -c1-7 <<<"$origin_sha"))."
  else
    echo "branch $branch differs on $m and on origin: local $(cut -c1-7 <<<"$local_sha"), origin $(cut -c1-7 <<<"$origin_sha"). Merge or push it by hand, or pick another branch." >&2
    exit 5
  fi
fi

args=(run --no-wait -q --title "$ref: $title" --cwd "$repo" --new-workspace worktree --label "cook=$ref" --label "cook-step=plan")
if [ "$(kv origin "$p")" = 1 ]; then
  mode=origin; args+=(--worktree-mode checkout-branch --branch "$branch")
  note="Continues on the branch from origin.${note:+ $note}"
elif [ "$(kv local "$p")" = 1 ]; then
  mode=local; args+=(--worktree-mode checkout-branch --branch "$branch")
  note="Continues on the local branch ($(kv ahead "$p") commits on top of $base). It is not on origin yet."
else
  mode=new; args+=(--worktree-mode branch-off --new-branch "$branch" --base "origin/$base")
fi
args+=(${extra[@]+"${extra[@]}"} "$(cat "$brief")")

if ! res=$(pas "$m" "${args[@]}" 2>&1); then
  echo "paseo run failed on $m: $(tail -n 1 <<<"$res")" >&2
  exit 6
fi
id=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27,}|^[0-9a-f]{7,}$' <<<"$res" | head -n 1)
[ -n "$id" ] || { echo "paseo run on $m printed no agent ID: $(tail -n 1 <<<"$res")" >&2; exit 6; }

printf 'build=%s:%s:%s\nagent=%s\nbranch=%s\nmode=%s\nnote=%s\n' "$m" "$id" "$ref" "$id" "$branch" "$mode" "$note"
