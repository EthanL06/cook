# shellcheck shell=bash
# Shared helpers for the cook scripts. Source it: . "$(dirname "$0")/lib.sh"
# A build string is <machine>:<agent-id>:<ref>. <machine> is "local" for this machine, else a Tailscale machine name.
# <ref> is the issue ref (#42, ENG-123) or the prompt slug, the same text as the start of the agent title "<ref>: <title>".

COOK_STATE=${COOK_STATE:-$HOME/.local/state/cook}
COOK_STEPS="plan build verify review learn blocked ready"
COOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COOK_TAILSCALE_APP=${COOK_TAILSCALE_APP:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}

pas() {
  local m=$1; shift
  if [ "$m" = local ]; then paseo "$@"; else paseo --host "ssh://$m" "$@"; fi
}

on() {
  local m=$1 script=$2; shift 2
  if [ "$m" = local ]; then bash -s -- "$@" <<<"$script"; else ssh -o BatchMode=yes -o ConnectTimeout=10 "$m" bash -s -- "$@" <<<"$script"; fi
}

kv() { sed -n "s/^$1=//p" <<<"$2" | head -n 1; }

# Machines that can hold builds: this one, plus each online Tailscale peer with ssh and paseo.
# COOK_MACHINES="local desktop-pc" limits the list.
cook_machines() {
  local out
  [ -n "${COOK_MACHINES:-}" ] && { echo "$COOK_MACHINES"; return; }
  if command -v tailscale >/dev/null 2>&1 || [ -x "$COOK_TAILSCALE_APP" ]; then
    out=$(python3 -I "$COOK_LIB_DIR/machines.py" --json 2>/dev/null | python3 -I -c 'import json, sys
for r in json.load(sys.stdin):
    if r.get("self") or (r.get("ssh") and r.get("paseo")):
        print("local" if r["self"] else r["name"])' 2>/dev/null)
  fi
  echo "${out:-local}"
}

# One line per cook build on a machine: <agent-id> TAB <step> TAB <ref> TAB <cwd>
cook_builds() {
  local m=$1 s
  for s in $COOK_STEPS; do
    pas "$m" ls -g --label "cook-step=$s" --json </dev/null 2>/dev/null \
      | jq -r --arg s "$s" '.[] | [.id, $s, (.name | split(": ")[0]), .cwd] | @tsv' 2>/dev/null
  done | sort -u -t$'\t' -k1,1
}

cook_events() {
  local f=".local/state/cook/events/$2.log"
  if [ "$1" = local ]; then cat "$COOK_STATE/events/$2.log" 2>/dev/null; else ssh -o BatchMode=yes -o ConnectTimeout=10 "$1" "cat $f" 2>/dev/null; fi
}
