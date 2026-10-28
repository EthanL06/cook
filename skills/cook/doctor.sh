#!/bin/bash
# Usage: doctor.sh
# Checks the tools cook needs on this machine and prints how to get each missing one. It installs nothing.
# Exit codes: 0 every required tool is there, 1 a required tool is missing.
set -u
missing=0

row() { printf '  %-4s %-16s %s\n' "$1" "$2" "$3"; }
need() {
  local name=$1 check=$2 hint=$3
  if eval "$check" >/dev/null 2>&1; then row ok "$name" ""; else row "--" "$name" "$hint"; missing=1; fi
}
want() {
  local name=$1 check=$2 hint=$3
  if eval "$check" >/dev/null 2>&1; then row ok "$name" ""; else row "  " "$name" "$hint"; fi
}

echo "Required"
need git           "command -v git"           "install git"
need gh            "gh auth status"           "brew install gh, then gh auth login"
need python3       "command -v python3"       "install Python 3"
need jq            "command -v jq"            "brew install jq"
need node          "command -v npx"           "install Node.js 20 or later (Lavish and AXI tools run with npx)"
need paseo         "command -v paseo"         "install Paseo: https://paseo.sh"
need agent-browser "command -v agent-browser" "brew install agent-browser, then agent-browser install"
need agent-cli     "command -v claude || command -v codex" "install Claude Code or Codex"

echo
echo "Review loop (default)"
want no-mistakes   "command -v no-mistakes"   "default review loop: https://kunchenguid.github.io/no-mistakes/"

echo
echo "Optional"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/cook/notify.env"
want notify        "grep -qE '^NOTIFY=(ntfy|pushover)' '$conf'" "pushes to your phone: put NOTIFY=ntfy and NTFY_TOPIC=<random> in $conf"
want tailscale     "command -v tailscale || [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]" "builds on other machines: https://tailscale.com/download"
want linear        "[ -n \"\${LINEAR_API_KEY:-}\" ]" "only for tracker: linear. Set LINEAR_API_KEY in your shell profile"
want mobbin-axi    "command -v mobbin-axi"    "UI references for mockups: npx -y mobbin-axi"

echo
if [ "$missing" = 1 ]; then
  echo "Some required tools are missing. Install them, then run doctor again."
  exit 1
fi
echo "Ready. In a project, run /cook-init."
