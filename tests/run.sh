#!/bin/bash
# Usage: tests/run.sh [-v] [-j <jobs>] [pattern ...]
# Runs each test_* function in tests/*.test.sh in its own sandbox: a temp HOME, COOK_STATE, XDG_* folders and TMPDIR,
# and a PATH that holds only the stubs in tests/stubs and the real tools that the scripts need.
# A pattern runs only the tests whose "<file>/<function>" name contains it. -v prints the output of each test.
# -j runs that many tests at the same time (default: the number of CPUs).
# Without a pattern, it runs shellcheck on every shell file first, when shellcheck is installed. CI installs it.
# Exit codes: 0 every test passed, 1 a test or shellcheck failed, 2 a required tool is missing.
set -u
TESTS="$(cd "$(dirname "$0")" && pwd -P)"
KIT="$(dirname "$TESTS")"

# Internal: run.sh --one <box> <test file> <function> runs one test and writes <box>/out and <box>/rc.
if [ "${1:-}" = --one ]; then
  box=$2 f=$3 fn=$4
  mkdir -p "$box/home" "$box/tmp" "$box/bin" "$box/stub" "$box/hosts"
  for x in "$COOK_TESTS_REAL"/* "$TESTS"/stubs/*; do ln -s "$x" "$box/bin/$(basename "$x")"; done
  env -i HOME="$box/home" PATH="$box/bin" TMPDIR="$box/tmp" LC_ALL=C TERM=dumb \
    COOK_STATE="$box/home/.local/state/cook" \
    XDG_CONFIG_HOME="$box/home/.config" XDG_STATE_HOME="$box/home/.local/state" \
    XDG_CACHE_HOME="$box/home/.cache" XDG_DATA_HOME="$box/home/.local/share" \
    COOK_TAILSCALE_APP="$box/no-tailscale-app" \
    GIT_CONFIG_GLOBAL="$box/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    KIT="$KIT" TESTS="$TESTS" T="$box" STUB_STATE="$box/stub" STUB_HOSTS="$box/hosts" \
    bash -c 'cd "$T" && . "$TESTS/lib.sh" && . "$1" && sandbox && "$2"' _ "$f" "$fn" >"$box/out" 2>&1 </dev/null
  echo $? >"$box/rc"
  exit 0
fi

verbose=0 jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v) verbose=1 ;;
    -j) jobs=${2:-}; shift ;;
    *) break ;;
  esac
  shift
done

work=$(mktemp -d "${TMPDIR:-/tmp}/cook-tests.XXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT

# Only real tools go on the PATH, so a gh, paseo or tailscale on this machine can never answer in place of a stub.
export COOK_TESTS_REAL="$work/real"
mkdir -p "$COOK_TESTS_REAL"
for t in bash sh env git python3 jq sed awk grep cat ls mkdir rm cp mv ln readlink dirname basename tr wc head tail \
  sort uniq cut date touch find xargs mktemp chmod df cksum hostname uname sleep tee diff cmp kill ps lsof od \
  comm expr stat paste; do
  p=$(type -P "$t") && ln -s "$p" "$COOK_TESTS_REAL/$t"
done
for t in bash git python3 jq; do
  [ -e "$COOK_TESTS_REAL/$t" ] || { echo "tests need $t" >&2; exit 2; }
done

lint=0
if [ "$#" = 0 ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    files=()
    while IFS= read -r f; do
      case "$(head -n 1 "$f")" in *python*) continue ;; esac
      files+=("$f")
    done < <(find "$KIT" -path "$KIT/.git" -prune -o -type f \( -name '*.sh' -o -path "$KIT/tests/stubs/*" \) -print | sort)
    if shellcheck "${files[@]}"; then echo "ok    shellcheck (${#files[@]} files)"; else echo "FAIL  shellcheck"; lint=1; fi
  else
    echo "skip  shellcheck: it is not installed"
  fi
fi

n=0
: >"$work/list"
for f in "$TESTS"/*.test.sh; do
  for fn in $(bash -c '. "$1"; declare -F' _ "$f" | awk '$3 ~ /^test_/ { print $3 }'); do
    name="$(basename "$f" .test.sh)/$fn"
    if [ "$#" -gt 0 ]; then
      hit=0
      for pat in "$@"; do case "$name" in *"$pat"*) hit=1 ;; esac; done
      [ "$hit" = 1 ] || continue
    fi
    n=$((n + 1))
    printf '%s\t%s\t%s\t%s\n' "$work/t$n" "$f" "$fn" "$name" >>"$work/list"
  done
done

cut -f1-3 "$work/list" | tr '\t' '\n' | xargs -P "$jobs" -n 3 "$0" --one

pass=0 nfail=0
while IFS=$'\t' read -r box _ _ name; do
  if [ "$(cat "$box/rc" 2>/dev/null)" = 0 ]; then
    pass=$((pass + 1))
    echo "ok    $name"
    [ "$verbose" = 1 ] && sed 's/^/      /' "$box/out"
  else
    nfail=$((nfail + 1))
    echo "FAIL  $name"
    sed 's/^/      /' "$box/out" | tail -n 40
  fi
done <"$work/list"

echo
echo "$pass passed, $nfail failed"
[ "$nfail" = 0 ] && [ "$lint" = 0 ]
