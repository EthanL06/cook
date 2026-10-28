#!/bin/bash
# Usage: install.sh add [--project <dir>]
#        install.sh update [--project <dir>]
#        install.sh remove [--project <dir>]
#        install.sh doctor [--fix [--yes]]
# Global (default): links each skill in skills/ into ~/.agents/skills and ~/.claude/skills, so a git pull updates them.
# --project <dir>: copies the skills into <dir>/.agents/skills (to commit and pin a version for a team) and links
#   <dir>/.claude/skills/<name> to them.
# It never replaces a skill of the same name that it did not install. It installs no other tool: run doctor for those.
# Exit codes: 0 done, 1 bad arguments, 2 one or more skills were skipped.
set -u
KIT="$(cd "$(dirname "$0")" && pwd -P)"
cmd=${1:-}; shift 2>/dev/null
project=""
if [ "${1:-}" = --project ]; then
  [ -n "${2:-}" ] || { echo "--project needs a folder" >&2; exit 1; }
  project="$(cd "$2" 2>/dev/null && pwd -P)" || { echo "no such folder: $2" >&2; exit 1; }
fi
skills=$(cd "$KIT/skills" && ls -d */ | tr -d /)
rc=0

ours() { [ -L "$1" ] && case "$(readlink "$1")" in "$KIT"/*) return 0 ;; esac; [ -f "$1/.cook-kit" ]; }

link_global() {
  local dir=$1 s
  mkdir -p "$dir"
  for s in $skills; do
    if [ -e "$dir/$s" ] && ! ours "$dir/$s"; then
      echo "  skipped $dir/$s: a skill with this name is already there"; rc=2; continue
    fi
    ln -sfn "$KIT/skills/$s" "$dir/$s"
    echo "  linked  $dir/$s"
  done
}

copy_project() {
  local s dst="$project/.agents/skills" links="$project/.claude/skills"
  mkdir -p "$dst" "$links"
  for s in $skills; do
    if [ -e "$dst/$s" ] && ! ours "$dst/$s"; then
      echo "  skipped $dst/$s: a skill with this name is already there"; rc=2; continue
    fi
    rm -rf "${dst:?}/${s:?}"
    cp -R "$KIT/skills/$s" "$dst/$s"
    git -C "$KIT" rev-parse --short HEAD >"$dst/$s/.cook-kit" 2>/dev/null || echo unknown >"$dst/$s/.cook-kit"
    if [ -L "$links/$s" ] || ! [ -e "$links/$s" ]; then ln -sfn "../../.agents/skills/$s" "$links/$s"; fi
    echo "  copied  $dst/$s"
  done
}

unlink_all() {
  local dir s
  for dir in "$@"; do
    for s in $skills; do
      if [ -L "$dir/$s" ] && ours "$dir/$s"; then rm "$dir/$s"; echo "  removed $dir/$s"
      elif [ -L "$dir/$s" ] && [ "$(readlink "$dir/$s")" = "../../.agents/skills/$s" ]; then rm "$dir/$s"; echo "  removed $dir/$s"
      elif [ -d "$dir/$s" ] && [ -f "$dir/$s/.cook-kit" ]; then rm -rf "${dir:?}/${s:?}"; echo "  removed $dir/$s"
      fi
    done
  done
}

case "$cmd" in
  add)
    if [ -n "$project" ]; then copy_project; else link_global "$HOME/.agents/skills"; link_global "$HOME/.claude/skills"; fi
    echo
    "$KIT/skills/cook/doctor.sh" || true
    ;;
  update)
    git -C "$KIT" pull -q --ff-only || { echo "git pull failed in $KIT" >&2; exit 1; }
    echo "cook is at $(git -C "$KIT" log -1 --format='%h %s')"
    if [ -n "$project" ]; then copy_project; else link_global "$HOME/.agents/skills"; link_global "$HOME/.claude/skills"; fi
    ;;
  remove)
    if [ -n "$project" ]; then unlink_all "$project/.claude/skills" "$project/.agents/skills"; else unlink_all "$HOME/.agents/skills" "$HOME/.claude/skills"; fi
    echo "Project files (.agents/cook.md, verifiers, recipes) stay. Delete them by hand if you want."
    ;;
  doctor)
    exec "$KIT/skills/cook/doctor.sh" "$@"
    ;;
  *)
    echo "usage: install.sh add|update|remove [--project <dir>] | install.sh doctor [--fix [--yes]]" >&2
    exit 1
    ;;
esac
exit "$rc"
