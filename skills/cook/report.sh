#!/bin/bash
# Usage: report.sh plan|build|verify|review|learn|blocked|ready <ref> <text> [url]
# Run by the build agent. Sets its cook-step label and appends one line to
# ~/.local/state/cook/events/<agent-id>.log:  COOK EVENT <utc time> <step> <ref> | <text> | <url or ->
# The hub, /cook-status and cleanup read that file. Paseo labels cannot carry text or links.
# Exit codes: 0 reported, 1 bad arguments, 2 not inside a Paseo agent, 3 label update failed, 4 event file not written.
set -u
. "$(dirname "$0")/lib.sh"
step=${1:-}; ref=${2:-}; text=${3:-}; url=${4:-}
valid=0
for s in $COOK_STEPS; do [ "$step" = "$s" ] && valid=1; done
[ "$valid" = 1 ] && [ -n "$ref" ] && [ -n "$text" ] || { echo "usage: report.sh ${COOK_STEPS// /|} <ref> <text> [url]" >&2; exit 1; }
[ -n "${PASEO_AGENT_ID:-}" ] || { echo "PASEO_AGENT_ID is not set: run this inside the Paseo build agent" >&2; exit 2; }

paseo agent update "$PASEO_AGENT_ID" --label "cook-step=$step" >/dev/null || exit 3
text=$(printf '%s' "$text" | tr '\n|' ' /')
line="COOK EVENT $(date -u +%Y-%m-%dT%H:%M:%SZ) $step $ref | $text | ${url:--}"
mkdir -p "$COOK_STATE/events" && echo "$line" >>"$COOK_STATE/events/$PASEO_AGENT_ID.log" || exit 4
echo "$line"
