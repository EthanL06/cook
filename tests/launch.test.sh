# launch.sh: start a build agent, with branch conflicts and failed launches.

brief() { printf 'COOK BUILD - read the cook skill and do steps 4 to 10.\n\nIssue: #42 Save recipes offline\n' >"$T/brief.md"; }

launch() {
  local m=${LAUNCH_MACHINE:-local}
  run "$S/launch.sh" --machine "$m" --repo "$1" --ref "#42" --title "Save recipes offline" \
    --branch "${2:-feat-offline}" --base main --brief "$T/brief.md" -- --provider claude --mode bypassPermissions
}

new_id() { kv agent "$out"; }

test_new_branch_branches_off_origin_base() {
  r=$(new_repo app)
  brief
  launch "$r"
  assert_rc 0
  assert_has "mode=new"
  id=$(new_id)
  assert_has "build=local:$id:#42"
  assert_called paseo "--worktree-mode branch-off --new-branch feat-offline --base origin/main"
  assert_called paseo "--provider claude --mode bypassPermissions"
  assert_eq "$(agent_field local "$id" '.labels["cook-step"]')" plan "step label"
  assert_eq "$(agent_field local "$id" '.labels.cook')" "#42" "cook label"
  assert_eq "$(agent_field local "$id" .name)" "#42: Save recipes offline" title
  w=$(agent_field local "$id" .cwd)
  assert_eq "$(git -C "$w" branch --show-current)" feat-offline "worktree branch"
  assert_eq "$(git -C "$w" rev-parse HEAD)" "$(git -C "$r" rev-parse origin/main)" "worktree head"
  agent_field local "$id" .prompt | grep -q "COOK BUILD" || fail "the brief is not the prompt"
}

test_branch_on_origin_is_checked_out() {
  r=$(new_repo app)
  other=$(new_repo app other)
  git -C "$other" checkout -qb feat-offline
  commit "$other" offline.js
  git -C "$other" push -q origin feat-offline
  brief
  launch "$r"
  assert_rc 0
  assert_has "mode=origin"
  assert_has "note=Continues on the branch from origin."
  assert_called paseo "--worktree-mode checkout-branch --branch feat-offline"
  w=$(agent_field local "$(new_id)" .cwd)
  assert_eq "$(git -C "$w" rev-parse HEAD)" "$(git -C "$other" rev-parse HEAD)" "worktree head is the origin branch"
}

test_local_branch_is_checked_out() {
  r=$(new_repo app)
  git -C "$r" branch feat-offline
  git -C "$r" checkout -q feat-offline
  commit "$r" a.js
  commit "$r" b.js
  git -C "$r" checkout -q main
  brief
  launch "$r"
  assert_rc 0
  assert_has "mode=local"
  assert_has "note=Continues on the local branch (2 commits on top of main). It is not on origin yet."
  w=$(agent_field local "$(new_id)" .cwd)
  assert_eq "$(git -C "$w" rev-parse HEAD)" "$(git -C "$r" rev-parse feat-offline)" "worktree head"
}

test_local_branch_behind_origin_moves_forward() {
  r=$(new_repo app)
  git -C "$r" branch feat-offline
  other=$(new_repo app other)
  git -C "$other" checkout -qb feat-offline
  commit "$other" offline.js
  git -C "$other" push -q origin feat-offline
  brief
  launch "$r"
  assert_rc 0
  assert_has "Moved the local branch forward to origin"
  assert_eq "$(git -C "$r" rev-parse feat-offline)" "$(git -C "$other" rev-parse HEAD)" "local branch"
}

test_local_branch_ahead_of_origin_keeps_its_commits() {
  r=$(new_repo app)
  git -C "$r" checkout -qb feat-offline
  commit "$r" a.js
  git -C "$r" push -q origin feat-offline
  commit "$r" b.js
  git -C "$r" checkout -q main
  sha=$(git -C "$r" rev-parse feat-offline)
  brief
  launch "$r"
  assert_rc 0
  assert_has "The local branch has commits that are not on origin yet."
  assert_eq "$(git -C "$r" rev-parse feat-offline)" "$sha" "local branch"
}

test_diverged_branch_stops() {
  r=$(new_repo app)
  git -C "$r" checkout -qb feat-offline
  commit "$r" mine.js
  git -C "$r" checkout -q main
  mine=$(git -C "$r" rev-parse feat-offline)
  other=$(new_repo app other)
  git -C "$other" checkout -qb feat-offline
  commit "$other" theirs.js
  git -C "$other" push -q origin feat-offline
  brief
  launch "$r"
  assert_rc 5
  assert_has "branch feat-offline differs on local and on origin"
  assert_eq "$(git -C "$r" rev-parse feat-offline)" "$mine" "local branch"
  assert_not_called paseo "run "
}

test_branch_in_another_worktree_stops() {
  r=$(new_repo app)
  w=$(worktree "$r" feat-offline)
  brief
  launch "$r"
  assert_rc 5
  assert_has "branch feat-offline is checked out in $w on local"
  assert_has "/cook resume #42"
  assert_not_called paseo "run "
}

test_paseo_run_failure_is_reported() {
  r=$(new_repo app)
  brief
  mkdir -p "$STUB_STATE/paseo/local"
  echo "Error: provider claude is not signed in" >"$STUB_STATE/paseo/local/fail-run"
  launch "$r"
  assert_rc 6
  assert_has "paseo run failed on local: Error: provider claude is not signed in"
  assert_lacks "build="
}

test_paseo_daemon_down_is_reported() {
  r=$(new_repo app)
  brief
  mkdir -p "$STUB_STATE/paseo/local"
  echo "Error: connect ECONNREFUSED" >"$STUB_STATE/paseo/local/fail-ls"
  launch "$r"
  assert_rc 3
  assert_has "the Paseo daemon on local does not answer: Error: connect ECONNREFUSED"
  assert_not_called paseo "run "
}

test_unreachable_machine_is_reported() {
  r=$(new_repo app box)
  brief
  down box
  LAUNCH_MACHINE=box launch "$r"
  assert_rc 3
  assert_has "cannot reach box over SSH"
  assert_not_called paseo "run "
}

test_remote_machine_launch() {
  r=$(new_repo app box)
  brief
  LAUNCH_MACHINE=box launch "$r"
  assert_rc 0
  id=$(new_id)
  assert_has "build=box:$id:#42"
  assert_called paseo "--host ssh://box run"
  w=$(agent_field box "$id" .cwd)
  case "$w" in "$STUB_HOSTS/box/.paseo/worktrees/"*) ;; *) fail "worktree is not on box: $w" ;; esac
}

test_missing_base_or_checkout_stops() {
  r=$(new_repo app)
  brief
  run "$S/launch.sh" --machine local --repo "$r" --ref "#42" --title t --branch feat-x --base release-9 --brief "$T/brief.md"
  assert_rc 4
  assert_has "the base branch release-9 is not on origin"
  run "$S/launch.sh" --machine local --repo "$T/nothing" --ref "#42" --title t --branch feat-x --base main --brief "$T/brief.md"
  assert_rc 4
  assert_has "no git checkout at $T/nothing"
  run "$S/launch.sh" --machine local --repo "$r" --ref "#42"
  assert_rc 1
  assert_not_called paseo "run "
}
