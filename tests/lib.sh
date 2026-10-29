# shellcheck shell=bash
# Helpers for the tests. tests/run.sh sources this file in each sandbox, then the test file, then runs one test.
# Globals from run.sh: KIT (this repo), T (the sandbox), STUB_STATE, STUB_HOSTS.
S="$KIT/skills/cook"
# shellcheck source=../skills/cook/lib.sh
. "$S/lib.sh"

sandbox() {
  case "$HOME" in "$T"/*) ;; *) echo "HOME is not in the sandbox" >&2; exit 1 ;; esac
  git config --global user.name "Test"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
  # Every github.com/acme repo is a bare repo in the sandbox, so origin URLs look real but stay local.
  git config --global url."$T/remote/".insteadOf "https://github.com/acme/"
  mkdir -p "$T/remote"
  touch "$STUB_STATE/calls.log"
}

# fail <message> [show-output]: ends the test. The message is the last line, so the runner's tail always shows it.
fail() { [ -n "${2:-}" ] && printf -- '--- output\n%s\n---\n' "$out"; echo "FAIL: $1"; exit 1; }

# run <cmd> ...: runs it and keeps its output (stdout and stderr) in $out and its exit code in $rc.
run() { out=$("$@" 2>&1); rc=$?; }
assert_rc() { [ "$rc" = "$1" ] || fail "exit code $rc, expected $1" show; }
assert_has() { grep -qF -- "$1" <<<"$out" || fail "output does not contain: $1" show; }
assert_lacks() { ! grep -qF -- "$1" <<<"$out" || fail "output contains: $1" show; }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-value}: got '$1', expected '$2'"; }
assert_file() { [ -e "$1" ] || fail "missing: $1"; }
assert_no_file() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "still there: $1"; }
assert_link() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ] || fail "$1 is not a link to $2"; }
calls() { grep "^$1 " "$STUB_STATE/calls.log"; }
assert_called() { calls "$1" | grep -qF -- "$2" || { cat "$STUB_STATE/calls.log"; fail "no '$1' call with: $2"; }; }
assert_not_called() { ! calls "$1" | grep -qF -- "$2" || fail "unexpected '$1' call with: $2"; }

# home_of <machine>: the HOME of a machine. "local" is this sandbox's HOME. Other machines are reached with the ssh stub.
home_of() { if [ "$1" = local ]; then echo "$HOME"; else echo "$STUB_HOSTS/$1"; fi; }
down() { mkdir -p "$STUB_STATE/down"; touch "$STUB_STATE/down/$1"; }

# new_repo <name> [machine]: a bare origin with one commit on main, and a checkout at <home>/Developer/<name>.
# Prints the checkout path. Its origin URL is https://github.com/acme/<name>.git.
new_repo() {
  local name=$1 home dir
  home=$(home_of "${2:-local}")
  dir="$home/Developer/$name"
  if [ ! -d "$T/remote/$name.git" ]; then
    git init -q --bare "$T/remote/$name.git"
    git clone -q "https://github.com/acme/$name.git" "$T/seed-$name" 2>/dev/null
    echo "# $name" >"$T/seed-$name/README.md"
    git -C "$T/seed-$name" add README.md
    git -C "$T/seed-$name" commit -qm "Initial commit"
    git -C "$T/seed-$name" push -q origin HEAD:main
  fi
  mkdir -p "$home/Developer"
  git clone -q "https://github.com/acme/$name.git" "$dir"
  echo "$dir"
}

# commit <dir> <file> [text]: writes the file and commits it.
commit() {
  echo "${3:-change}" >>"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -qm "Change $2"
}

# worktree <repo> <branch> [machine]: a Paseo-style worktree on a new branch from origin/main. Prints its path.
worktree() {
  local home path
  home=$(home_of "${3:-local}")
  path="$home/.paseo/worktrees/$(printf '%s' "$2" | cksum | cut -c1-8)/${2//\//-}"
  mkdir -p "$(dirname "$path")"
  git -C "$1" worktree add -q -b "$2" "$path" origin/main
  echo "$path"
}

# agent <machine> <id> <ref> <step> <cwd> [status]: a Paseo agent with the cook labels.
agent() {
  local d="$STUB_STATE/paseo/$1"
  mkdir -p "$d"
  jq -n --arg id "$2" --arg ref "$3" --arg step "$4" --arg cwd "$5" --arg status "${6:-idle}" '{
    id: $id, name: "\($ref): Test build", status: $status, archived: false, cwd: $cwd,
    provider: "claude", model: "opus", mode: "bypassPermissions",
    labels: {cook: $ref, "cook-step": $step}, prompt: "", messages: []}' >"$d/$2.json"
}
agent_json() { cat "$STUB_STATE/paseo/$1/$2.json"; }
agent_field() { jq -r "$3" "$STUB_STATE/paseo/$1/$2.json"; }
forget_agent() { rm -f "$STUB_STATE/paseo/$1/$2.json"; }

# pr <branch> <STATE> <head sha> [url]: the PR that the gh stub returns for the branch.
pr() {
  mkdir -p "$STUB_STATE/gh/pr"
  echo "$2 $3 ${4:-https://github.com/acme/app/pull/57}" >"$STUB_STATE/gh/pr/${1//\//-}"
}

# event <machine> <agent id> <utc time> <step> <ref> <text> [url]: one line in the build's event log.
event() {
  local d
  d="$(home_of "$1")/.local/state/cook/events"
  mkdir -p "$d"
  echo "COOK EVENT $3 $4 $5 | $6 | ${7:--}" >>"$d/$2.log"
}

# tool <name> ...: an empty command that exits 0, for the doctor checks.
tool() { local t; for t in "$@"; do printf '#!/bin/sh\nexit 0\n' >"$T/bin/$t"; chmod +x "$T/bin/$t"; done; }
untool() { local t; for t in "$@"; do rm -f "$T/bin/$t"; done; }

# cookmd <repo> <yaml header lines>: writes <repo>/.agents/cook.md.
cookmd() {
  mkdir -p "$1/.agents"
  printf -- '---\n%s\n---\n\n# Project\n' "$2" >"$1/.agents/cook.md"
}
