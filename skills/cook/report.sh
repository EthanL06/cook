#!/bin/bash
# Usage: report.sh [--brief <file>] [--spec <file>] [--receipt <file>] plan|build|verify|review|learn|blocked|ready <ref> <text> [url]
# Run by the build agent, in its worktree. Sets its cook-step label, appends one line to
# ~/.local/state/cook/events/<agent-id>.log:  COOK EVENT <utc time> <step> <ref> | <text> | <url or ->
# and updates the build's run state in ~/.local/state/cook/runs/ (see run.py), which /cook resume reads.
# The hub, /cook-status and cleanup read these files. Paseo labels cannot carry text or links.
#   --brief <file>    the build brief, with the first report.
#   --spec <file>     the approved spec, with the report that starts the build. After that, a plan report is refused.
#   --receipt <file>  the /cook-verify receipt, with the report after each verify run.
# Exit codes: 0 reported, 1 bad arguments, 2 not inside a Paseo agent, 3 label update failed, 4 event file not written,
#   5 refused because the spec is approved already, 6 run state not written.
set -u
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
opts=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --brief|--spec|--receipt) [ -n "${2:-}" ] || { echo "$1 needs a file" >&2; exit 1; }; opts+=("$1" "$2"); shift 2 ;;
    *) break ;;
  esac
done
step=${1:-}; ref=${2:-}; text=${3:-}; url=${4:-}
valid=0
for s in $COOK_STEPS; do [ "$step" = "$s" ] && valid=1; done
[ "$valid" = 1 ] && [ -n "$ref" ] && [ -n "$text" ] || { echo "usage: report.sh [--brief <file>] [--spec <file>] [--receipt <file>] ${COOK_STEPS// /|} <ref> <text> [url]" >&2; exit 1; }
[ -n "${PASEO_AGENT_ID:-}" ] || { echo "PASEO_AGENT_ID is not set: run this inside the Paseo build agent" >&2; exit 2; }

text=$(printf '%s' "$text" | tr '\n|' ' /')
state=(python3 -I "$COOK_LIB_DIR/run.py" update --step "$step" --ref "$ref" --agent "$PASEO_AGENT_ID" --text "$text" --url "$url"
  ${opts[@]+"${opts[@]}"})
"${state[@]}" --check || exit $?

paseo agent update "$PASEO_AGENT_ID" --label "cook-step=$step" >/dev/null || exit 3
line="COOK EVENT $(date -u +%Y-%m-%dT%H:%M:%SZ) $step $ref | $text | ${url:--}"
mkdir -p "$COOK_STATE/events" && echo "$line" >>"$COOK_STATE/events/$PASEO_AGENT_ID.log" || exit 4
COOK_STATE="$COOK_STATE" "${state[@]}" || exit 6
echo "$line"
