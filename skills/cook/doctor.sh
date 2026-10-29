#!/bin/bash
# Usage: doctor.sh [--fix [--yes]] [--quick] [--repo <dir>]
# Checks the tools cook needs. Inside a repo with .agents/cook.md it checks what that project uses
# (tracker, review loop, browser, ui_refs, notify). Elsewhere it checks the defaults.
# --fix   lists the install commands for what is missing, asks once, runs only what you approve, then checks again.
#         Steps that need an account, a password or a secret are never run. They are listed for you to do.
# --yes   with --fix: run the commands without the question. For an agent, after you said yes in the chat.
# --quick skips the checks when the last full run passed less than 24 hours ago for the same kit and cook.md.
# Exit codes: 0 every required tool is there, 1 a required tool is missing, 2 bad arguments.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
COOK_TAILSCALE_APP=${COOK_TAILSCALE_APP:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}
fix=0 yes=0 quick=0 repo=$PWD
while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix) fix=1 ;;
    --yes) yes=1 ;;
    --quick) quick=1 ;;
    --repo) repo=${2:-}; shift ;;
    *) echo "usage: doctor.sh [--fix [--yes]] [--quick] [--repo <dir>]" >&2; exit 2 ;;
  esac
  shift
done

cfg() { python3 -I "$here/config.py" --repo "$repo" get "$1" "$2" 2>/dev/null || echo "$2"; }
cookmd=$(python3 -I "$here/config.py" --repo "$repo" path 2>/dev/null) || cookmd=""
tracker=$(cfg tracker github) review=$(cfg review no-mistakes) browser=$(cfg browser agent-browser)
ui_refs=$(cfg ui_refs none) notify=$(cfg notify on)

state="${XDG_STATE_HOME:-$HOME/.local/state}/cook"
stamp="$state/doctor.ok"
key="$(cd "$here" && git rev-parse HEAD 2>/dev/null || cat "$here/.cook-kit" 2>/dev/null) $cookmd $( [ -n "$cookmd" ] && cksum <"$cookmd")"
if [ "$quick" = 1 ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$key" ] && [ -z "$(find "$stamp" -mmin +1440)" ]; then
  echo "doctor: ok (checked in the last 24 hours)"
  exit 0
fi

has() { command -v "$1" >/dev/null 2>&1; }
cached() { npx --no -- "$1" --help >/dev/null 2>&1; }
brew_or() { if has brew; then echo "brew install $1"; else echo "$2"; fi; }
# Node can be missing now and installed first in the same --fix run, so npm and npx steps only need a way to get it.
node_soon() { has npx || has brew; }
via_node() { node_soon && echo "$1"; }

rows=() fixes=() manual=() missing=0
# check <group> <required|optional> <name> <ok?> <fix command or ""> <what to do by hand, or "">
check() {
  local group=$1 need=$2 name=$3 ok=$4 cmd=$5 hand=$6 mark
  if [ "$ok" = 1 ]; then mark=ok
  elif [ "$need" = required ]; then mark=MISSING; missing=1
  else mark=-
  fi
  rows+=("$group|$mark|$name|$( [ "$ok" = 1 ] || echo "${cmd:-$hand}")")
  [ "$ok" = 1 ] && return
  if [ -n "$cmd" ]; then fixes+=("$name|$cmd"); else manual+=("$name$( [ "$need" = optional ] && echo " (optional)"): $hand"); fi
}
yn() { if eval "$1" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

run_checks() {
  rows=() fixes=() manual=() missing=0
  local G="Core" problems
  if [ -n "$cookmd" ]; then
    problems=$(python3 -I "$here/config.py" --repo "$repo" check 2>&1 >/dev/null | sed 1d | sed 's/^ *//' | paste -sd ';' - | sed 's/;/; /g')
    check "Project" required "cook.md" "$( [ -z "$problems" ] && echo 1 || echo 0)" "" "fix $cookmd: $problems"
  fi
  check "$G" required git           "$(yn 'has git')"     "$(brew_or git '')" "install git from https://git-scm.com"
  check "$G" required python3       "$(yn 'has python3')" ""                  "install Python 3 from https://www.python.org"
  check "$G" required jq            "$(yn 'has jq')"      "$(brew_or jq '')"  "install jq from https://jqlang.org"
  check "$G" required node          "$(yn 'has npx')"     "$(brew_or node '')" "install Node.js 20 or later from https://nodejs.org"
  check "$G" required gh            "$(yn 'has gh')"      "$(brew_or gh '')"  "install the GitHub CLI from https://cli.github.com"
  if has gh; then
    check "$G" required "gh sign-in" "$(yn 'gh auth status')" "" "run: gh auth login"
  fi
  check "$G" required "claude or codex" "$(yn 'has claude || has codex')" "" \
    "install one and sign in: npm install -g @anthropic-ai/claude-code, or npm install -g @openai/codex"
  check "$G" required paseo         "$(yn 'has paseo')"   "$(via_node 'npm install -g @getpaseo/cli')" "install Paseo from https://paseo.sh/download"
  if has paseo; then
    check "$G" required "paseo daemon" "$(yn 'paseo ls -q')" "" "open the Paseo app, or run: paseo"
  fi
  check "$G" required lavish-axi    "$(yn 'cached lavish-axi')" "$(via_node 'npx -y lavish-axi --version')" "install Node.js first, then run: npx -y lavish-axi --version"

  G="Browser ($browser)"
  case "$browser" in
    agent-browser)
      check "$G" required agent-browser "$(yn 'has agent-browser')" "$(brew_or agent-browser "$(via_node 'npm install -g agent-browser')")" "install Node.js first, then: npm install -g agent-browser"
      check "$G" required "agent-browser Chrome" "$(yn 'compgen -G "$HOME/.agent-browser/browsers/chrome-*"')" "agent-browser install" "" ;;
    chrome-devtools-axi|playwright-axi)
      check "$G" required "$browser" "$(yn "cached $browser")" "$(via_node "npx -y $browser --help")" "install Node.js first" ;;
    *) check "$G" required "$browser" 0 "" "unknown browser in cook.md: use agent-browser, chrome-devtools-axi or playwright-axi" ;;
  esac

  G="Tracker ($tracker)"
  case "$tracker" in
    github) check "$G" required "GitHub Issues" "$(yn 'has gh')" "" "uses gh, see Core" ;;
    linear)
      check "$G" required linear-sdk-axi "$(yn 'cached linear-sdk-axi')" "$(via_node 'npx -y linear-sdk-axi --help')" "install Node.js first"
      check "$G" required LINEAR_API_KEY "$( [ -n "${LINEAR_API_KEY:-}" ] && echo 1 || echo 0)" "" \
        "make a personal API key in Linear (Settings > Security & access) and export LINEAR_API_KEY in your shell profile" ;;
    none) ;;
    *) check "$G" required "$tracker" 0 "" "unknown tracker in cook.md: use github, linear or none" ;;
  esac

  G="Review loop ($review)"
  case "$review" in
    no-mistakes) check "$G" required no-mistakes "$(yn 'has no-mistakes')" \
      "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh" "" ;;
    greptile) check "$G" required "Greptile loop skill" \
      "$(yn 'compgen -G "$HOME/.agents/skills/*greptile*" || compgen -G "$HOME/.claude/skills/*greptile*" || compgen -G "$repo/.agents/skills/*greptile*"')" "" \
      "install a Greptile review-loop skill and connect Greptile to the GitHub repo (https://greptile.com)" ;;
    none) ;;
    *) check "$G" required "$review" 0 "" "unknown review in cook.md: use no-mistakes, greptile or none" ;;
  esac

  G="UI references ($ui_refs)"
  case "$ui_refs" in
    mobbin)
      check "$G" required mobbin-axi "$(yn 'cached mobbin-axi')" "$(via_node 'npx -y mobbin-axi --help')" "install Node.js first"
      if cached mobbin-axi; then
        check "$G" required "Mobbin sign-in" "$(yn 'npx --no -- mobbin-axi auth status | grep -q "authenticated: true"')" "" \
          "needs a Mobbin account. Run: npx -y mobbin-axi login (or set ui_refs: none in cook.md)"
      fi ;;
    none) ;;
    *) check "$G" required "$ui_refs" 0 "" "unknown ui_refs in cook.md: use mobbin or none" ;;
  esac

  G="Optional"
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/cook/notify.env"
  if [ "$notify" != off ]; then
    check "$G" optional "phone pushes" "$(yn "grep -qE '^NOTIFY=(ntfy|pushover|none)' '$conf'")" "" \
      "install the ntfy app, pick a long random topic, and put NOTIFY=ntfy and NTFY_TOPIC=<topic> in $conf"
  fi
  check "$G" optional tailscale "$(yn 'has tailscale || [ -x "$COOK_TAILSCALE_APP" ]')" "" \
    "only for builds on other machines: https://tailscale.com/download"
}

report() {
  local last="" r group mark name hint
  for r in "${rows[@]}"; do
    IFS='|' read -r group mark name hint <<<"$r"
    [ "$group" != "$last" ] && { [ -n "$last" ] && echo; echo "$group"; last=$group; }
    printf '  %-8s %-22s %s\n' "$mark" "$name" "$hint"
  done
  echo
}

echo "cook doctor${cookmd:+ for $(basename "$(dirname "$(dirname "$cookmd")")")}"
[ -n "$cookmd" ] || echo "(no .agents/cook.md here: checking the defaults)"
echo
run_checks
report

if [ "$fix" = 1 ] && [ "${#fixes[@]}" -gt 0 ]; then
  echo "These commands install what is missing:"
  for f in "${fixes[@]}"; do printf '  %-22s %s\n' "${f%%|*}" "${f#*|}"; done
  echo
  if [ "$yes" != 1 ]; then
    if [ -r /dev/tty ] && [ -t 1 ]; then
      printf 'Run these %s commands now? [y/N] ' "${#fixes[@]}"
      read -r answer </dev/tty
      case "$answer" in y|Y|yes) yes=1 ;; esac
    else
      echo "Not run. Ask the user, then run: doctor.sh --fix --yes"
    fi
  fi
  if [ "$yes" = 1 ]; then
    for f in "${fixes[@]}"; do
      echo "> ${f#*|}"
      bash -c "${f#*|}" || echo "  failed: ${f%%|*}. Do it by hand."
    done
    echo
    echo "Checking again."
    echo
    run_checks
    report
  fi
fi

if [ "${#manual[@]}" -gt 0 ]; then
  echo "Do these yourself (they need an account, a password, a secret or an app):"
  for m in "${manual[@]}"; do echo "  - $m"; done
  echo
fi

if [ "$missing" = 1 ]; then
  [ "$fix" = 1 ] || [ "${#fixes[@]}" -eq 0 ] || echo "Run doctor.sh --fix to install the missing tools."
  rm -f "$stamp"
  exit 1
fi
mkdir -p "$state" && echo "$key" >"$stamp"
echo "Ready.${cookmd:- In a project, run /cook-init.}"
exit 0
