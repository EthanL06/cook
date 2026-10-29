#!/bin/bash
# Usage: tracker.sh view <ref>
#        tracker.sh search <words>
#        tracker.sh create <title> <body-file>          prints the new ref
#        tracker.sh comment <ref> <body-file>
#        tracker.sh state <ref> in-progress|in-review
#        tracker.sh url <ref>
#        tracker.sh branch <ref>                        the tracker's own branch name, if it has one
# One interface over the tracker set in cook.md (tracker: github | linear | none).
# Refs: GitHub "#42" or "42", Linear "ENG-123". With "none", every command is a no-op that exits 0.
# Exit codes: 0 done, 1 bad arguments, 2 the tracker command failed, 3 not supported by this tracker, 4 cook.md is not valid.
set -u
cmd=${1:-}; shift 2>/dev/null
L="npx -y linear-sdk-axi"
num() { echo "${1#\#}"; }

[ -n "$cmd" ] || { echo "usage: tracker.sh view|search|create|comment|state|url|branch ..." >&2; exit 1; }
tracker=$(python3 -I "$(dirname "$0")/config.py" get tracker github) || exit 4
[ "$tracker" = none ] && { [ "$cmd" = url ] || [ "$cmd" = branch ] || echo "tracker is none: nothing to do"; exit 0; }

case "$tracker:$cmd" in
  github:view)    gh issue view "$(num "$1")" --comments || exit 2 ;;
  github:search)  gh issue list --state open --search "$*" --limit 10 || exit 2 ;;
  github:create)  u=$(gh issue create --title "$1" --body-file "$2") || exit 2; echo "#${u##*/}" ;;
  github:comment) gh issue comment "$(num "$1")" --body-file "$2" >/dev/null || exit 2 ;;
  github:state)
    # GitHub issues have no in-progress state. A label shows it, and the PR's "Closes #N" closes the issue on merge.
    label="cook:$2"
    gh label create "$label" --color BFD4F2 >/dev/null 2>&1
    other=cook:in-progress; [ "$2" = in-progress ] && other=cook:in-review
    gh issue edit "$(num "$1")" --add-label "$label" --remove-label "$other" >/dev/null 2>&1 \
      || gh issue edit "$(num "$1")" --add-label "$label" >/dev/null || exit 2 ;;
  github:url)     gh issue view "$(num "$1")" --json url -q .url || exit 2 ;;
  github:branch)  exit 0 ;;
  linear:view)    $L issue view "$1" --full --comments || exit 2 ;;
  linear:search)  $L issue search "$*" --team "$(python3 -I "$(dirname "$0")/config.py" get linear_team)" || exit 2 ;;
  linear:create)  $L issue create --title "$1" --body-file "$2" --team "$(python3 -I "$(dirname "$0")/config.py" get linear_team)" \
                    | grep -oE '[A-Z][A-Z0-9]*-[0-9]+' | head -n 1 | grep . || exit 2 ;;
  linear:comment) $L issue comment "$1" --body-file "$2" >/dev/null || exit 2 ;;
  linear:state)
    case "$2" in in-progress) s="In Progress" ;; in-review) s="In Review" ;; *) exit 1 ;; esac
    $L issue update "$1" --state "$s" >/dev/null || exit 2 ;;
  linear:url)     $L issue view "$1" | grep -oE 'https://linear\.app/[^ "]+' | head -n 1 ;;
  linear:branch)  $L issue view "$1" | sed -nE 's/.*[Bb]ranch[^:]*: *"?([^" ]+)"?.*/\1/p' | head -n 1 ;;
  *) echo "tracker '$tracker' does not support '$cmd'" >&2; exit 3 ;;
esac
