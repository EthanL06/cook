# shellcheck shell=bash disable=SC2154 # out, rc and the sandbox paths come from tests/lib.sh
# resume.sh: continue a build after the agent or the machine stopped.

ID=agent-1111-aaaa

# start_build [machine]: a worktree, its build agent and the first report, as launch.sh and step 4 make them.
# Sets r (checkout), w (worktree) and M (machine).
start_build() {
  M=${1:-local}
  r=$(new_repo app "$M")
  w=$(worktree "$r" feat-offline "$M")
  agent "$M" "$ID" "#42" plan "$w"
  cat >"$T/brief.md" <<'EOF'
COOK BUILD - read the cook skill and do steps 4 to 10.

Issue: #42 Save recipes offline
Branch: feat-offline   Base: main
Machine: studio   Tailscale DNS: none   IP: none
EOF
  rep --brief "$T/brief.md" plan "#42" "Reading the code."
  rep plan "#42" "Spec v1 is ready to review." "http://studio:4387/s/1"
}

# rep <report.sh args>: report.sh as the build agent runs it, in the worktree on its machine.
rep() {
  local a q=""
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  if [ "$M" = local ]; then
    (cd "$w" && PASEO_AGENT_ID=${AGENT:-$ID} "$S/report.sh" "$@") >/dev/null || fail "report.sh $*"
  else
    # shellcheck disable=SC2029 # the test paths are the same on both sides
    ssh "$M" "cd $w && PASEO_AGENT_ID=${AGENT:-$ID} $S/report.sh $q" >/dev/null || fail "report.sh $*"
  fi
}

# Step 4 and /cook-verify keep .lavish/ and .context/ out of git, so they never make a worktree dirty.
ignore_cook_files() { printf '.lavish/\n.context/\n' >>"$(git -C "$w" rev-parse --path-format=absolute --git-common-dir)/info/exclude"; }

approve() {
  ignore_cook_files
  mkdir -p "$w/.lavish"
  echo "<h1>Offline recipes spec</h1>" >"$w/.lavish/cook-spec.html"
  rep --spec "$w/.lavish/cook-spec.html" build "#42" "Spec approved. Build started."
}

verify_fail() {
  commit "$w" offline.js
  git -C "$w" push -q origin feat-offline
  rep verify "#42" "Build done. Verify started."
  mkdir -p "$w/.context/verify/1"
  printf 'VERIFY: FAIL\nTarget: feat-offline vs main\n- [FAIL] offline page - blank\n' >"$w/.context/verify/1/receipt.md"
  rep --receipt "$w/.context/verify/1/receipt.md" verify "#42" "Verify failed: offline page is blank."
}

resume() { run env COOK_MACHINES="${MACHINES:-local}" "$S/resume.sh" "$@"; }
new_agent() { kv build "$out" | cut -d: -f2; }
state() { jq -r "$1" "$(home_of "$M")/.local/state/cook/runs/app-42.json"; }

test_crash_after_spec_approval_starts_a_new_agent_in_the_worktree() {
  start_build
  approve
  commit "$w" offline.js
  forget_agent local "$ID"
  resume "#42" -- --provider codex --mode full-access
  assert_rc 0
  assert_has "resumed=started"
  assert_has "step=build"
  n=$(new_agent)
  [ -n "$n" ] && [ "$n" != "$ID" ] || fail "no new agent"
  assert_eq "$(agent_field local "$n" .cwd)" "$w" "new agent's worktree"
  assert_eq "$(agent_field local "$n" '.labels["cook-step"]')" build "new agent's step label"
  assert_eq "$(agent_field local "$n" .name)" "#42: Save recipes offline" "new agent's title"
  assert_called paseo "--provider codex --mode full-access"
  assert_not_called paseo "--new-workspace"
  p=$(agent_field local "$n" .prompt)
  grep -q "^COOK RESUME" <<<"$p" || fail "the prompt is not a resume brief"
  grep -q "^Continue at: build" <<<"$p" || fail "continue step"
  grep -q "Continue it from step 5 (build)" <<<"$p" || fail "section"
  grep -qF "The copy is $HOME/.local/state/cook/runs/app-42/spec.html" <<<"$p" || fail "spec copy"
  grep -q "Do not change it, and do not ask for approval again" <<<"$p" || fail "spec rule"
  grep -qF "Head: $(git -C "$w" rev-parse HEAD)" <<<"$p" || fail "head"
  grep -qF "Original brief: $HOME/.local/state/cook/runs/app-42/brief.md" <<<"$p" || fail "brief copy"

  run env PASEO_AGENT_ID="$n" bash -c "cd '$w' && '$S/report.sh' plan '#42' 'Spec v2.'"
  assert_rc 5
  AGENT=$n rep build "#42" "Resumed at build."
  assert_eq "$(state .agent_id)" "$n" "agent in the run state"
  assert_eq "$(state '.agents | join(",")')" "$ID,$n" "agents in the run state"
}

test_crash_during_verify_sends_the_live_agent_a_message() {
  start_build
  approve
  verify_fail
  resume "#42"
  assert_rc 0
  assert_has "resumed=sent"
  assert_has "build=local:$ID:#42"
  assert_not_called paseo "run "
  msg=$(agent_field local "$ID" '.messages[-1]')
  grep -q "^Continue at: verify" <<<"$msg" || fail "continue step"
  grep -q "Last verification: FAIL" <<<"$msg" || fail "last verdict"
  grep -qF "Receipt: $HOME/.local/state/cook/runs/app-42/receipt-1.md" <<<"$msg" || fail "receipt copy"
  grep -q "Read it before you change code" <<<"$msg" || fail "receipt rule"
  grep -q "Approved on" <<<"$msg" || fail "approved spec"
}

test_crash_during_verify_with_an_archived_agent_keeps_its_provider() {
  start_build
  approve
  verify_fail
  jq '.archived = true | .provider = "claude" | .model = "opus" | .mode = "bypassPermissions"' \
    "$STUB_STATE/paseo/local/$ID.json" >"$T/a.json" && mv "$T/a.json" "$STUB_STATE/paseo/local/$ID.json"
  resume "#42"
  assert_rc 0
  assert_has "resumed=started"
  assert_has "replaces=$ID"
  assert_called paseo "--provider claude --model opus --mode bypassPermissions"
  n=$(new_agent)
  assert_eq "$(agent_field local "$n" '.labels["cook-step"]')" verify "new label"
  assert_eq "$(agent_field local "$ID" '.labels["cook-step"]')" resumed "old label"
}

test_verify_pass_on_the_same_head_continues_at_the_pr() {
  start_build
  approve
  commit "$w" offline.js
  mkdir -p "$w/.context/verify/2"
  printf 'VERIFY: PASS\n' >"$w/.context/verify/2/receipt.md"
  rep --receipt "$w/.context/verify/2/receipt.md" verify "#42" "Verify passed."
  forget_agent local "$ID"
  resume "#42" --dry-run
  assert_rc 0
  assert_has "action=start"
  assert_has "Continue at: pr"
  assert_has "Continue it from step 7 (pull request)"
  commit "$w" later.js
  resume "#42" --dry-run
  assert_has "Continue at: verify"
  assert_not_called paseo "run "
}

test_blocked_build_continues_at_the_step_before_the_block() {
  start_build
  approve
  verify_fail
  rep blocked "#42" "No test user. Next: reply \"use seed user 3\""
  resume "#42" --dry-run
  assert_rc 0
  assert_has "action=send"
  assert_has "Continue at: verify"
}

test_crash_before_approval_continues_the_spec_loop() {
  start_build
  forget_agent local "$ID"
  resume "#42" --dry-run
  assert_rc 0
  assert_has "Continue at: plan"
  assert_has "Not approved yet. The last draft is http://studio:4387/s/1"
}

test_missing_worktree_stops_until_asked() {
  start_build
  approve
  verify_fail
  sha=$(git -C "$w" rev-parse HEAD)
  forget_agent local "$ID"
  rm -rf "$w"
  git -C "$r" worktree prune
  resume "#42"
  assert_rc 4
  assert_has "the worktree $w is gone. The branch feat-offline has the last saved commit ${sha:0:7}"
  assert_has "--new-worktree"
  assert_not_called paseo "run "
  resume "#42" --new-worktree
  assert_rc 0
  assert_has "resumed=started"
  assert_called paseo "--worktree-mode checkout-branch --branch feat-offline"
  n=$(new_agent)
  nw=$(agent_field local "$n" .cwd)
  assert_eq "$(git -C "$nw" rev-parse HEAD)" "$sha" "head of the new worktree"
}

test_missing_worktree_and_branch_never_loses_the_commit() {
  start_build
  approve
  commit "$w" offline.js
  rep verify "#42" "Build done. Verify started."
  sha=$(git -C "$w" rev-parse HEAD)
  forget_agent local "$ID"
  git -C "$r" worktree remove --force "$w"
  git -C "$r" branch -D feat-offline >/dev/null
  resume "#42" --new-worktree
  assert_rc 4
  assert_has "the last saved commit ${sha:0:7} is on no branch"
  assert_has "git -C $r branch feat-offline-saved ${sha:0:7}"
  assert_not_called paseo "run "
}

test_dirty_worktree_needs_the_users_go_ahead() {
  start_build
  approve
  commit "$w" offline.js
  echo "half done" >"$w/sync.js"
  echo "edit" >>"$w/README.md"
  forget_agent local "$ID"
  resume "#42"
  assert_rc 5
  assert_has "has 2 uncommitted file(s)"
  assert_has "sync.js"
  assert_has "--dirty-ok"
  assert_not_called paseo "run "
  resume "#42" --dirty-ok
  assert_rc 0
  p=$(agent_field local "$(new_agent)" .prompt)
  grep -q "Worktree changes: 2 uncommitted file(s) from before the stop. The user knows." <<<"$p" || fail "dirty note"
  grep -q "Never discard them" <<<"$p" || fail "keep rule"
  assert_file "$w/sync.js"
}

test_head_that_lost_the_saved_commit_stops() {
  start_build
  approve
  commit "$w" offline.js
  rep verify "#42" "Build done. Verify started."
  git -C "$w" reset -q --hard HEAD~1
  forget_agent local "$ID"
  resume "#42"
  assert_rc 4
  assert_has "does not have the last saved commit"
  assert_has "git reflog"
}

test_worktree_on_another_branch_stops() {
  start_build
  approve
  git -C "$w" checkout -qb something-else
  forget_agent local "$ID"
  resume "#42"
  assert_rc 4
  assert_has "is on branch something-else, not feat-offline"
}

test_running_agent_is_left_alone() {
  start_build
  approve
  jq '.status = "running"' "$STUB_STATE/paseo/local/$ID.json" >"$T/a.json" && mv "$T/a.json" "$STUB_STATE/paseo/local/$ID.json"
  resume "#42"
  assert_rc 6
  assert_has "is running on local"
  assert_not_called paseo "send"
}

test_second_resume_does_not_start_a_second_agent() {
  start_build
  approve
  forget_agent local "$ID"
  resume "#42"
  assert_rc 0
  resume "#42"
  assert_rc 6
  assert_has "another cook agent works in $w"
}

test_remote_build_resumes_over_ssh() {
  MACHINES="local box" start_build box
  approve
  verify_fail
  forget_agent box "$ID"
  MACHINES="local box" resume "#42"
  assert_rc 0
  assert_has "build=box:"
  assert_called paseo "--host ssh://box run"
  assert_eq "$(agent_field box "$(new_agent)" .cwd)" "$w" "worktree on box"
}

test_list_shows_builds_to_resume() {
  start_build
  approve
  echo wip >"$w/wip.js"
  forget_agent local "$ID"
  r2=$(new_repo web)
  w2=$(worktree "$r2" feat-csv)
  agent local agent-2222-bbbb csv-export plan "$w2"
  (cd "$w2" && PASEO_AGENT_ID=agent-2222-bbbb "$S/report.sh" ready csv-export "CSV export. PR is ready." https://github.com/acme/web/pull/3) >/dev/null
  down box
  MACHINES="local box" resume
  assert_rc 0
  assert_has "#42"
  assert_has "build"
  assert_has "gone"
  assert_has "1 uncommitted file(s)"
  assert_has "app-42"
  assert_lacks "csv-export "
  assert_has "1 done build(s) not shown"
  assert_has "MACHINE box does not answer"
}

test_unknown_and_ambiguous_refs() {
  start_build
  r2=$(new_repo web)
  w2=$(worktree "$r2" feat-web)
  agent local agent-3333-cccc "#42" plan "$w2"
  (cd "$w2" && PASEO_AGENT_ID=agent-3333-cccc "$S/report.sh" plan "#42" "Reading the code.") >/dev/null
  resume "#7"
  assert_rc 2
  assert_has "no run state matches #7"
  resume "#42"
  assert_rc 3
  assert_has "app-42"
  assert_has "web-42"
  resume web-42 --dry-run
  assert_rc 0
  assert_has "agent=agent-3333-cccc"
}

test_ready_build_has_nothing_to_resume() {
  start_build
  rep ready "#42" "Offline recipes. PR is ready." https://github.com/acme/app/pull/57
  resume "#42"
  assert_rc 0
  assert_has "Nothing to resume"
  assert_not_called paseo "run "
  assert_not_called paseo "send"
}
