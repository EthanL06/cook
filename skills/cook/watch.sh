#!/bin/bash
# Usage: watch.sh <machine>:<agent-id>:<ref> ...
# Run by the hub. Prints each new COOK EVENT line of each build once, as "<machine> <line>".
# When a build's PR is merged or closed, it prints one "merged" or "closed" event, so the hub can suggest a cleanup.
# It also allows each pending permission request of a build's agent and prints a "permission" event.
# Exits 0 when the PR of every build is merged or closed.
# COOK_WATCH_INTERVAL seconds between polls (default 60). The seen lines are kept in COOK_WATCH_DIR, so a restart prints no line twice.
# Exit codes: 0 done, 1 bad arguments.
set -u
. "$(dirname "$0")/lib.sh"
[ "$#" -gt 0 ] || { echo "usage: watch.sh <machine>:<agent-id>:<ref> ..." >&2; exit 1; }

state=${COOK_WATCH_DIR:-${TMPDIR:-/tmp}/cook-watch}
mkdir -p "$state"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

while :; do
  all_done=1
  for b in "$@"; do
    IFS=: read -r m id ref <<<"$b"
    seen="$state/$id"
    touch "$seen"
    events=$(cook_events "$m" "$id")
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -qxF -- "$line" "$seen" && continue
      echo "$m $line"
      echo "$line" >>"$seen"
    done <<<"$events"
    # Some agent CLIs still ask for a few commands in their no-prompt mode. The hub allows them so a build does not stall.
    while IFS=$'\t' read -r req tool; do
      [ -n "$req" ] || continue
      pas "$m" permit allow "$id" "$req" >/dev/null 2>&1 && echo "$m COOK EVENT $(now) permission $ref | allowed $tool ($req) | -"
    done < <(pas "$m" permit ls --json 2>/dev/null | jq -r --arg id "$id" '.[] | select(.agentId | startswith($id)) | [.id, .name] | @tsv' 2>/dev/null)
    # A build can go on after "ready" (for example to fix review comments), so the watch ends only when the PR does.
    url=$(awk -F' [|] ' '$3 ~ /\/pull\/[0-9]+$/ { u = $3 } END { print u }' <<<"$events")
    key=
    case $([ -n "$url" ] && gh pr view "$url" --json state -q .state 2>/dev/null) in
      MERGED) key="merged $ref"; text="PR merged. Ready to clean up." ;;
      CLOSED) key="closed $ref"; text="PR closed without a merge. You can clean it up." ;;
      *) all_done=0 ;;
    esac
    if [ -n "$key" ] && ! grep -qxF -- "$key" "$seen"; then
      echo "$m COOK EVENT $(now) $key | $text | $url"
      echo "$key" >>"$seen"
    fi
  done
  [ "$all_done" = 1 ] && exit 0
  sleep "${COOK_WATCH_INTERVAL:-60}"
done
