#!/bin/bash
# Usage: tests/run.sh [-v] [pattern ...]
# Runs each test_* function in tests/*.test.sh in its own sandbox: a temp HOME, COOK_STATE, XDG_* folders and TMPDIR,
# and a PATH that holds only the stubs in tests/stubs and the real tools that the scripts need.
# A pattern runs only the tests whose file or function name contains it. -v prints the output of each test.
# Exit codes: 0 every test passed, 1 a test failed, 2 a required tool is missing.
set -u
TESTS="$(cd "$(dirname "$0")" && pwd -P)"
KIT="$(dirname "$TESTS")"
verbose=0
[ "${1:-}" = -v ] && { verbose=1; shift; }

work=$(mktemp -d "${TMPDIR:-/tmp}/cook-tests.XXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT

# Only real tools go on the PATH, so a gh, paseo or tailscale on this machine can never answer in place of a stub.
real="$work/real"
mkdir -p "$real"
for t in bash sh env git python3 jq sed awk grep cat ls mkdir rm cp mv ln readlink dirname basename tr wc head tail \
  sort uniq cut date touch find xargs mktemp chmod df cksum hostname uname sleep tee diff cmp kill ps lsof od \
  comm expr stat paste; do
  p=$(type -P "$t") && ln -s "$p" "$real/$t"
done
for t in bash git python3 jq; do
  [ -e "$real/$t" ] || { echo "tests need $t" >&2; exit 2; }
done

tests=()
for f in "$TESTS"/*.test.sh; do
  for fn in $(bash -c '. "$1"; declare -F' _ "$f" | awk '$3 ~ /^test_/ { print $3 }'); do
    name="$(basename "$f" .test.sh)/$fn"
    if [ "$#" -gt 0 ]; then
      hit=0
      for pat in "$@"; do case "$name" in *"$pat"*) hit=1 ;; esac; done
      [ "$hit" = 1 ] || continue
    fi
    tests+=("$f|$fn|$name")
  done
done

pass=0 nfail=0
n=0
for t in ${tests[@]+"${tests[@]}"}; do
  IFS='|' read -r f fn name <<<"$t"
  n=$((n + 1))
  box="$work/t$n"
  mkdir -p "$box/home" "$box/tmp" "$box/bin" "$box/stub" "$box/hosts"
  for x in "$real"/* "$TESTS"/stubs/*; do ln -s "$x" "$box/bin/$(basename "$x")"; done
  env -i HOME="$box/home" PATH="$box/bin" TMPDIR="$box/tmp" LC_ALL=C TERM=dumb \
    COOK_STATE="$box/home/.local/state/cook" \
    XDG_CONFIG_HOME="$box/home/.config" XDG_STATE_HOME="$box/home/.local/state" \
    XDG_CACHE_HOME="$box/home/.cache" XDG_DATA_HOME="$box/home/.local/share" \
    COOK_TAILSCALE_APP="$box/no-tailscale-app" \
    GIT_CONFIG_GLOBAL="$box/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    KIT="$KIT" TESTS="$TESTS" T="$box" STUB_STATE="$box/stub" STUB_HOSTS="$box/hosts" \
    bash -c 'cd "$T" && . "$TESTS/lib.sh" && . "$1" && sandbox && "$2"' _ "$f" "$fn" >"$box/out" 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then
    pass=$((pass + 1))
    echo "ok    $name"
    [ "$verbose" = 1 ] && sed 's/^/      /' "$box/out"
  else
    nfail=$((nfail + 1))
    echo "FAIL  $name"
    sed 's/^/      /' "$box/out" | tail -n 40
  fi
done

echo
echo "$pass passed, $nfail failed"
[ "$nfail" = 0 ]
