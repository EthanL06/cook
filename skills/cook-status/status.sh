#!/bin/bash
# Usage: status.sh [ref] [--watch]
# Read-only. Shows every cook build on every machine: step, who it waits on, time in the step, machine and the last event.
# It also reads the run state (see cook/run.py): a build whose agent is gone shows "resume", and the detail view shows
# the approved spec, the last verify result and the head commit. Builds that wait on you come first. With a ref, it shows that build in detail. --watch redraws every COOK_STATUS_INTERVAL
# seconds (default 10). It never sends a message to a build agent.
# The step durations ("usually takes") come from the event logs of past builds on this machine.
# Exit codes: 0 shown, 1 bad arguments, 2 no build matches the ref.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../cook/lib.sh"

ref="" watch=0
for a in "$@"; do
  case "$a" in
    --watch) watch=1 ;;
    -*) echo "usage: status.sh [ref] [--watch]" >&2; exit 1 ;;
    *) ref=$a ;;
  esac
done

gather() {
  local m id step r cwd js
  for m in $(cook_machines); do
    cook_up "$m" || { printf 'DOWN\t%s\n' "$m"; continue; }
    while IFS=$'\t' read -r -u 3 id step r cwd; do
      printf 'BUILD\t%s\t%s\t%s\t%s\t%s\n' "$m" "$id" "$step" "$r" "$cwd"
      cook_events "$m" "$id" | sed 's/^/EV\t/'
    done 3< <(cook_builds "$m")
    while IFS= read -r -u 3 js; do
      [ -n "$js" ] || continue
      printf 'RUN\t%s\t%s\n' "$m" "$js"
      cook_events "$m" "$(jq -r .agent_id <<<"$js")" | sed 's/^/EV\t/'
    done 3< <(cook_runs "$m")
  done
  for f in "$COOK_STATE"/events/*.log; do
    [ -f "$f" ] && sed 's/^/HIST\t/' "$f"
  done
}


show() { gather | python3 -I "$here/status.py" "$ref"; }

if [ "$watch" = 1 ]; then
  while :; do
    out=$(show)
    clear
    printf '%s\n\ncook-status · %s · every %ss · Ctrl-C to stop\n' "$out" "$(date +%H:%M:%S)" "${COOK_STATUS_INTERVAL:-10}"
    sleep "${COOK_STATUS_INTERVAL:-10}"
  done
fi
show
