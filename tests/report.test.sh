# report.sh and run.py: step labels, event lines, and the run state of a build through its steps.

ID=agent-1111-aaaa

# A build: a repo, its worktree on feat-offline, and the Paseo agent in it. The shell is in the worktree.
build() {
  r=$(new_repo app)
  w=$(worktree "$r" feat-offline)
  agent local "$ID" "#42" plan "$w"
  cd "$w" || fail cd
  export PASEO_AGENT_ID=$ID
  cat >"$T/brief.md" <<'EOF'
COOK BUILD - read the cook skill and do steps 4 to 10.

Issue: #42 Save recipes offline
URL: https://github.com/acme/app/issues/42
Branch: feat-offline   Base: main
Machine: studio   Tailscale DNS: none   IP: none

Intake answers (word for word):
- Done: a saved recipe opens with wifi off
EOF
}
R() { "$S/report.sh" "$@"; }
state() { jq -r "$1" "$HOME/.local/state/cook/runs/app-42.json"; }
events() { cat "$HOME/.local/state/cook/events/$ID.log"; }
receipt() { printf 'VERIFY: %s\nTarget: feat-offline@abc vs main\n' "$1" >"$T/receipt.md"; }

test_needs_a_paseo_agent_and_valid_arguments() {
  build
  unset PASEO_AGENT_ID
  run R plan "#42" "Reading the code."
  assert_rc 2
  export PASEO_AGENT_ID=$ID
  run R cooking "#42" "Reading the code."
  assert_rc 1
  run R plan "#42"
  assert_rc 1
  run R --spec
  assert_rc 1
  assert_no_file "$HOME/.local/state/cook/events/$ID.log"
}

test_first_report_saves_the_build_facts() {
  build
  run R --brief "$T/brief.md" plan "#42" "Reading the code."
  assert_rc 0
  assert_has "plan #42 | Reading the code. | -"
  assert_eq "$(agent_field local $ID '.labels["cook-step"]')" plan label
  assert_eq "$(events | wc -l | tr -d ' ')" 1 "event lines"
  assert_eq "$(state .ref)" "#42" ref
  assert_eq "$(state .step)" plan step
  assert_eq "$(state .agent_id)" "$ID" agent
  assert_eq "$(state .branch)" feat-offline branch
  assert_eq "$(state .base)" main base
  assert_eq "$(state .title)" "Save recipes offline" title
  assert_eq "$(state .machine)" studio machine
  assert_eq "$(state .cwd)" "$w" cwd
  assert_eq "$(state .repo)" "$r" repo
  assert_eq "$(state .head)" "$(git rev-parse HEAD)" head
  assert_eq "$(state .origin)" "https://github.com/acme/app.git" origin
  cmp -s "$(state .brief)" "$T/brief.md" || fail "the brief copy differs"
  [ "$(wc -l <"$HOME/.local/state/cook/runs/app-42.json" | tr -d ' ')" = 1 ] || fail "the state is not one line"
  ls -a "$HOME/.local/state/cook/runs" | grep -q '^\.app' && fail "a temp file is left"
  true
}

test_text_with_pipes_and_newlines_stays_one_field() {
  build
  run R plan "#42" "$(printf 'Spec v2: a | b\nnext line')" "http://studio:4387/s/1"
  assert_rc 0
  assert_has "plan #42 | Spec v2: a / b next line | http://studio:4387/s/1"
  assert_eq "$(state .spec_url)" "http://studio:4387/s/1" "spec url"
}

test_label_failure_changes_nothing() {
  build
  R --brief "$T/brief.md" plan "#42" "Reading the code." >/dev/null
  before=$(cat "$HOME/.local/state/cook/runs/app-42.json")
  echo "Error: daemon restarting" >"$STUB_STATE/paseo/local/fail-update"
  run R build "#42" "Spec approved."
  assert_rc 3
  assert_eq "$(events | wc -l | tr -d ' ')" 1 "event lines"
  assert_eq "$(cat "$HOME/.local/state/cook/runs/app-42.json")" "$before" "run state"
}

test_approved_spec_is_kept_and_never_redone() {
  build
  R --brief "$T/brief.md" plan "#42" "Spec v1 is ready." "http://studio:4387/s/1" >/dev/null
  mkdir -p .lavish
  echo "<h1>Spec v3</h1>" >.lavish/cook-spec.html
  run R --spec .lavish/cook-spec.html plan "#42" "Spec v3."
  assert_rc 1
  assert_has "--spec is for the approved spec"
  run R --spec .lavish/cook-spec.html build "#42" "Spec approved. Build started."
  assert_rc 0
  assert_eq "$(state .spec.source)" "$w/.lavish/cook-spec.html" "spec source"
  assert_eq "$(state .spec.url)" "http://studio:4387/s/1" "spec url"
  cmp -s "$(state .spec.copy)" .lavish/cook-spec.html || fail "the spec copy differs"
  approved=$(state .spec.approved)

  run R plan "#42" "Spec v4."
  assert_rc 5
  assert_has "refused: the spec of #42 is approved"
  assert_eq "$(agent_field local $ID '.labels["cook-step"]')" build "label after the refused plan"
  assert_eq "$(state .step)" build "step after the refused plan"
  events | grep -q "Spec v4" && fail "the refused report has an event line"

  run R --spec .lavish/cook-spec.html build "#42" "Same spec again."
  assert_rc 0
  echo "<h1>Spec v5</h1>" >.lavish/cook-spec.html
  run R --spec .lavish/cook-spec.html build "#42" "Changed spec."
  assert_rc 5
  assert_has "is approved already"
  assert_eq "$(state .spec.approved)" "$approved" "approval time"
  grep -q "Spec v3" "$(state .spec.copy)" || fail "the approved copy changed"
}

test_verify_failures_then_blocked() {
  build
  R --brief "$T/brief.md" plan "#42" "Reading the code." >/dev/null
  R build "#42" "Spec approved." >/dev/null
  commit "$w" offline.js
  R verify "#42" "Build done. Verify started." >/dev/null
  receipt FAIL
  run R --receipt "$T/receipt.md" verify "#42" "Verify failed: offline page is blank. Repairing."
  assert_rc 0
  assert_eq "$(state .verify.verdict)" FAIL verdict
  assert_eq "$(state .verify.attempts)" 1 attempts
  assert_eq "$(state .verify.head)" "$(git rev-parse HEAD)" "verified head"
  receipt FAIL
  R --receipt "$T/receipt.md" verify "#42" "Verify failed again." >/dev/null
  receipt BLOCKED
  run R --receipt "$T/receipt.md" blocked "#42" "No test user for offline sync. Next: reply \"use seed user 3\"" https://github.com/acme/app/issues/42
  assert_rc 0
  assert_eq "$(agent_field local $ID '.labels["cook-step"]')" blocked label
  assert_eq "$(state .step)" blocked step
  assert_eq "$(state .resume_step)" verify "resume step"
  assert_eq "$(state .verify.verdict)" BLOCKED verdict
  assert_eq "$(state .verify.attempts)" 3 attempts
  assert_eq "$(state '.verify_history | map(.verdict) | join(",")')" "FAIL,FAIL,BLOCKED" history
  for n in 1 2 3; do assert_file "$HOME/.local/state/cook/runs/app-42/receipt-$n.md"; done
  head -n 1 "$HOME/.local/state/cook/runs/app-42/receipt-1.md" | grep -q FAIL || fail "receipt 1 is not the FAIL receipt"
  events | tail -n 1 | grep -qF 'blocked #42 | No test user for offline sync. Next: reply "use seed user 3" | https://github.com/acme/app/issues/42' \
    || fail "blocked event line"

  mkdir -p "$HOME/.config/cook"
  echo NOTIFY=ntfy >"$HOME/.config/cook/notify.env"
  run env COOK_NOTIFY_DRY_RUN=1 "$S/notify.sh" blocked "#42" "No test user. Next: reply \"use seed user 3\""
  assert_rc 0
  assert_has "title=Blocked: needs you - #42"

  R build "#42" "Unblocked. Build continues." >/dev/null
  assert_eq "$(state .resume_step)" build "resume step after unblock"
}

test_a_file_that_is_not_a_receipt_is_refused() {
  build
  R plan "#42" "Reading the code." >/dev/null
  echo "all good" >"$T/receipt.md"
  run R --receipt "$T/receipt.md" verify "#42" "Verify done."
  assert_rc 1
  assert_has "is not a /cook-verify receipt"
  assert_eq "$(state .verify)" null "verify state"
  assert_eq "$(events | wc -l | tr -d ' ')" 1 "event lines"
}

test_pr_url_and_ready() {
  build
  R plan "#42" "Reading the code." >/dev/null
  R review "#42" "PR is open." https://github.com/acme/app/pull/57 >/dev/null
  R ready "#42" "Offline recipes. PR is ready." https://github.com/acme/app/pull/57 >/dev/null
  assert_eq "$(state .pr)" https://github.com/acme/app/pull/57 pr
  assert_eq "$(state .resume_step)" ready "resume step"
}

test_run_py_get_list_and_remove() {
  build
  R --brief "$T/brief.md" plan "#42" "Reading the code." >/dev/null
  run python3 -I "$S/run.py" get 42 branch
  assert_rc 0
  assert_eq "$out" feat-offline branch
  run python3 -I "$S/run.py" get app-42 title
  assert_eq "$out" "Save recipes offline" title
  run python3 -I "$S/run.py" get "#7"
  assert_rc 2
  run python3 -I "$S/run.py" list
  assert_eq "$(jq -r .key <<<"$out")" app-42 "list key"
  run python3 -I "$S/run.py" remove "#42"
  assert_rc 0
  assert_no_file "$HOME/.local/state/cook/runs/app-42.json"
  assert_no_file "$HOME/.local/state/cook/runs/app-42"
}
