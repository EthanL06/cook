# install.sh: add, update and remove, global and --project.

# A clone of this kit with a bare origin, so "update" can pull. Prints nothing. The clone is $T/kit.
kit() {
  mkdir -p "$T/kitsrc"
  cp "$KIT/install.sh" "$T/kitsrc/"
  cp -R "$KIT/skills" "$T/kitsrc/"
  find "$T/kitsrc" -name __pycache__ -prune -exec rm -rf {} +
  git -C "$T/kitsrc" init -q
  git -C "$T/kitsrc" add -A
  git -C "$T/kitsrc" commit -qm "Kit"
  git init -q --bare "$T/remote/cook.git"
  git -C "$T/kitsrc" push -q "https://github.com/acme/cook.git" HEAD:main
  git clone -q "https://github.com/acme/cook.git" "$T/kit"
}

# Pushes a new skill to the kit's origin, as an upstream release would.
release_skill() {
  mkdir -p "$T/kitsrc/skills/$1"
  printf -- '---\nname: %s\n---\n' "$1" >"$T/kitsrc/skills/$1/SKILL.md"
  git -C "$T/kitsrc" add -A
  git -C "$T/kitsrc" commit -qm "Add $1"
  git -C "$T/kitsrc" push -q "https://github.com/acme/cook.git" HEAD:main
}

skills_of_kit() { (cd "$T/kit/skills" && ls); }

test_add_global_links_every_skill_in_both_folders() {
  kit
  run "$T/kit/install.sh" add
  assert_rc 0
  for s in $(skills_of_kit); do
    assert_link "$HOME/.agents/skills/$s" "$T/kit/skills/$s"
    assert_link "$HOME/.claude/skills/$s" "$T/kit/skills/$s"
  done
  assert_has "cook doctor"
}

test_add_global_twice_is_safe() {
  kit
  "$T/kit/install.sh" add >/dev/null 2>&1
  run "$T/kit/install.sh" add
  assert_rc 0
  assert_lacks skipped
}

test_add_global_keeps_a_skill_that_has_the_same_name() {
  kit
  mkdir -p "$HOME/.claude/skills/cook"
  echo mine >"$HOME/.claude/skills/cook/SKILL.md"
  mkdir -p "$HOME/.agents/skills"
  ln -s "$T/other/cook-status" "$HOME/.agents/skills/cook-status"
  run "$T/kit/install.sh" add
  assert_rc 2
  assert_has "skipped $HOME/.claude/skills/cook: a skill with this name is already there"
  assert_has "skipped $HOME/.agents/skills/cook-status"
  assert_eq "$(cat "$HOME/.claude/skills/cook/SKILL.md")" mine "the user's own skill"
  assert_link "$HOME/.agents/skills/cook-status" "$T/other/cook-status"
  assert_link "$HOME/.agents/skills/cook" "$T/kit/skills/cook"
  assert_link "$HOME/.claude/skills/cook-status" "$T/kit/skills/cook-status"
}

test_update_global_pulls_and_links_a_new_skill() {
  kit
  "$T/kit/install.sh" add >/dev/null 2>&1
  release_skill cook-extra
  run "$T/kit/install.sh" update
  assert_rc 0
  assert_has "cook is at"
  assert_has "Add cook-extra"
  assert_link "$HOME/.agents/skills/cook-extra" "$T/kit/skills/cook-extra"
  assert_link "$HOME/.claude/skills/cook-extra" "$T/kit/skills/cook-extra"
}

test_update_global_removes_links_to_skills_the_kit_dropped() {
  kit
  release_skill cook-old
  git -C "$T/kit" pull -q
  "$T/kit/install.sh" add >/dev/null 2>&1
  assert_link "$HOME/.agents/skills/cook-old" "$T/kit/skills/cook-old"
  git -C "$T/kitsrc" rm -rq skills/cook-old
  git -C "$T/kitsrc" commit -qm "Drop cook-old"
  git -C "$T/kitsrc" push -q "https://github.com/acme/cook.git" HEAD:main
  run "$T/kit/install.sh" update
  assert_rc 0
  assert_no_file "$HOME/.agents/skills/cook-old"
  assert_no_file "$HOME/.claude/skills/cook-old"
  assert_has "removed $HOME/.agents/skills/cook-old"
}

test_update_stops_when_the_pull_fails() {
  kit
  "$T/kit/install.sh" add >/dev/null 2>&1
  commit "$T/kit" local.txt
  release_skill cook-extra
  run "$T/kit/install.sh" update
  assert_rc 1
  assert_has "git pull failed in $T/kit"
  assert_no_file "$HOME/.agents/skills/cook-extra"
}

test_remove_global_removes_only_its_own_links() {
  kit
  mkdir -p "$HOME/.claude/skills/cook"
  echo mine >"$HOME/.claude/skills/cook/SKILL.md"
  mkdir -p "$HOME/.agents/skills/other-skill"
  "$T/kit/install.sh" add >/dev/null 2>&1
  run "$T/kit/install.sh" remove
  assert_rc 0
  for s in $(skills_of_kit); do assert_no_file "$HOME/.agents/skills/$s"; done
  assert_no_file "$HOME/.claude/skills/cook-status"
  assert_eq "$(cat "$HOME/.claude/skills/cook/SKILL.md")" mine "the user's own skill"
  assert_file "$HOME/.agents/skills/other-skill"
}

test_add_project_copies_and_links_the_skills() {
  kit
  p=$(new_repo app)
  run "$T/kit/install.sh" add --project "$p"
  assert_rc 0
  sha=$(git -C "$T/kit" rev-parse --short HEAD)
  for s in $(skills_of_kit); do
    assert_file "$p/.agents/skills/$s/SKILL.md"
    [ -L "$p/.agents/skills/$s" ] && fail "$s is a link, expected a copy"
    assert_eq "$(cat "$p/.agents/skills/$s/.cook-kit")" "$sha" "$s/.cook-kit"
    assert_link "$p/.claude/skills/$s" "../../.agents/skills/$s"
  done
  assert_file "$p/.claude/skills/cook/SKILL.md"
  assert_no_file "$HOME/.agents/skills/cook"
}

test_add_project_keeps_a_skill_that_has_the_same_name() {
  kit
  p=$(new_repo app)
  mkdir -p "$p/.agents/skills/cook-status" "$p/.claude/skills/cook-verify"
  echo team >"$p/.agents/skills/cook-status/SKILL.md"
  echo team >"$p/.claude/skills/cook-verify/SKILL.md"
  run "$T/kit/install.sh" add --project "$p"
  assert_rc 2
  assert_has "skipped $p/.agents/skills/cook-status: a skill with this name is already there"
  assert_has "skipped $p/.claude/skills/cook-verify: a skill with this name is already there"
  assert_eq "$(cat "$p/.agents/skills/cook-status/SKILL.md")" team "the team's cook-status"
  assert_eq "$(cat "$p/.claude/skills/cook-verify/SKILL.md")" team "the team's cook-verify"
  assert_file "$p/.agents/skills/cook/.cook-kit"
}

test_update_project_copies_the_new_version() {
  kit
  p=$(new_repo app)
  "$T/kit/install.sh" add --project "$p" >/dev/null 2>&1
  old=$(cat "$p/.agents/skills/cook/.cook-kit")
  release_skill cook-extra
  run "$T/kit/install.sh" update --project "$p"
  assert_rc 0
  new=$(git -C "$T/kit" rev-parse --short HEAD)
  [ "$old" != "$new" ] || fail "the kit did not move"
  assert_eq "$(cat "$p/.agents/skills/cook/.cook-kit")" "$new" ".cook-kit after update"
  assert_file "$p/.agents/skills/cook-extra/SKILL.md"
  assert_link "$p/.claude/skills/cook-extra" "../../.agents/skills/cook-extra"
}

test_remove_project_keeps_the_project_files() {
  kit
  p=$(new_repo app)
  cookmd "$p" "base: main"
  mkdir -p "$p/.agents/skills/verifier-tests" "$p/.agents/recipes"
  "$T/kit/install.sh" add --project "$p" >/dev/null 2>&1
  run "$T/kit/install.sh" remove --project "$p"
  assert_rc 0
  for s in $(skills_of_kit); do
    assert_no_file "$p/.agents/skills/$s"
    assert_no_file "$p/.claude/skills/$s"
  done
  assert_file "$p/.agents/cook.md"
  assert_file "$p/.agents/skills/verifier-tests"
  assert_file "$p/.agents/recipes"
  assert_has "Project files (.agents/cook.md, verifiers, recipes) stay."
}

test_bad_arguments() {
  kit
  run "$T/kit/install.sh"
  assert_rc 1
  assert_has "usage: install.sh"
  run "$T/kit/install.sh" add --project
  assert_rc 1
  assert_has "--project needs a folder"
  run "$T/kit/install.sh" add --project "$T/nowhere"
  assert_rc 1
  assert_has "no such folder: $T/nowhere"
  assert_no_file "$HOME/.agents/skills/cook"
}
