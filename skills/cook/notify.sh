#!/bin/bash
# Usage: notify.sh plan|blocked|ready <ref> <message> [url]
# Sends one push to your phone. Settings live in ~/.config/cook/notify.env (never in the repo):
#   NOTIFY=ntfy       NTFY_TOPIC=<a long random topic>  [NTFY_SERVER=https://ntfy.sh] [NTFY_TOKEN=...]
#   NOTIFY=pushover   PUSHOVER_TOKEN=...  PUSHOVER_USER=...
#   NOTIFY=none       no pushes
# "notify: off" in the project's cook.md also turns pushes off for that project.
# COOK_NOTIFY_DRY_RUN=1 prints the push instead of sending it.
# Exit codes: 0 sent, dry run or turned off, 1 bad arguments, 3 not configured, 4 the service refused it.
set -u
kind=${1:-}; ref=${2:-}; msg=${3:-}; url=${4:-}
case "$kind" in
  plan)    title="Plan ready for you - $ref";       ntfy_prio=default; po_prio=0; tags=memo ;;
  blocked) title="Blocked: needs you - $ref";       ntfy_prio=high;    po_prio=1; tags=rotating_light ;;
  ready)   title="Ready for review - $ref";         ntfy_prio=default; po_prio=0; tags=white_check_mark ;;
  *) echo "usage: notify.sh plan|blocked|ready <ref> <message> [url]" >&2; exit 1 ;;
esac
[ -n "$ref" ] && [ -n "$msg" ] || { echo "ref and message are required" >&2; exit 1; }

conf="${XDG_CONFIG_HOME:-$HOME/.config}/cook/notify.env"
# shellcheck source=/dev/null
[ -f "$conf" ] && . "$conf"
project=$(python3 -I "$(dirname "$0")/config.py" get notify on 2>/dev/null)
[ "$project" = off ] && { echo "not sent: notify is off in cook.md"; exit 0; }
service=${NOTIFY:-}
[ "$service" = none ] && { echo "not sent: NOTIFY=none"; exit 0; }
[ -n "$service" ] || { echo "not sent: no NOTIFY in $conf (see docs/guide.md, ntfy)" >&2; exit 3; }

if [ -n "${COOK_NOTIFY_DRY_RUN:-}" ]; then
  printf 'service=%s\ntitle=%s\nmessage=%s\nurl=%s\n' "$service" "$title" "$msg" "$url"
  exit 0
fi

case "$service" in
  ntfy)
    [ -n "${NTFY_TOPIC:-}" ] || { echo "not sent: NTFY_TOPIC is not set in $conf" >&2; exit 3; }
    args=(-sS --max-time 10 -H "Title: $title" -H "Priority: $ntfy_prio" -H "Tags: $tags" -d "$msg")
    [ -n "$url" ] && args+=(-H "Click: $url")
    [ -n "${NTFY_TOKEN:-}" ] && args+=(-H "Authorization: Bearer $NTFY_TOKEN")
    res=$(curl "${args[@]}" "${NTFY_SERVER:-https://ntfy.sh}/$NTFY_TOPIC" 2>&1)
    [[ "$res" == *'"event":"message"'* ]] || { echo "ntfy refused: $res" >&2; exit 4; }
    ;;
  pushover)
    [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ] || { echo "not sent: PUSHOVER_TOKEN and PUSHOVER_USER are not set in $conf" >&2; exit 3; }
    args=(-sS --max-time 10 --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USER"
      --form-string "title=$title" --form-string "message=$msg" --form-string "priority=$po_prio")
    [ -n "$url" ] && args+=(--form-string "url=$url")
    res=$(curl "${args[@]}" https://api.pushover.net/1/messages.json 2>&1)
    [[ "$res" == *'"status":1'* ]] || { echo "Pushover refused: $res" >&2; exit 4; }
    ;;
  *) echo "not sent: unknown NOTIFY=$service (use ntfy, pushover or none)" >&2; exit 3 ;;
esac
echo "sent: $title"
