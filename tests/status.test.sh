# /cook-status: status.sh and status.py, from Paseo labels, event logs and the run state.

status() { run env COOK_MACHINES="${MACHINES:-local}" "$KIT/skills/cook-status/status.sh" "$@"; }

# build <id> <ref> <branch> <step>: a worktree, its agent and a report of <step>. Sets r and w.
build() {
  [ -n "${r:-}" ] || r=$(new_repo app)
  w=$(worktree "$r" "$3")
  printf '.lavish/\n.context/\n' >>"$r/.git/info/exclude"
  agent local "$1" "$2" "$4" "$w"
  (cd "$w" && PASEO_AGENT_ID=$1 "$S/report.sh" "$4" "$2" "${5:-Working.}" "${6:-}") >/dev/null || fail "report.sh"
}

test_no_builds() {
  status
  assert_rc 0
  assert_has "No cook builds are running."
}

test_builds_that_wait_on_you_come_first() {
  build a-build "#1" feat-one build "Spec approved. Build started."
  build a-plan "#2" feat-two plan "Spec v1 is ready to review." "http://studio:4387/s/2"
  status
  assert_rc 0
  first=$(sed -n 2p <<<"$out")
  case "$first" in "#2 "*plan*you*) ;; *) fail "first row: $first" ;; esac
  assert_has "Spec v1 is ready to review.  http://studio:4387/s/2"
  assert_has "Spec approved. Build started."
  assert_has "1 build waits on you. Oldest: #2"
}

test_build_whose_agent_is_gone_waits_on_a_resume() {
  build a1 "#42" feat-offline verify "Build done. Verify started."
  forget_agent local a1
  status
  assert_rc 0
  assert_has "you (resume)"
  assert_has "agent is gone. Run /cook resume #42"
  status "#42"
  assert_rc 0
  assert_has "agent    gone from Paseo. Continue the build with /cook resume #42"
}

test_detail_shows_the_saved_spec_and_verify_result() {
  build a1 "#42" feat-offline plan "Spec v1." "http://studio:4387/s/1"
  mkdir -p "$w/.lavish" "$w/.context/verify/1"
  echo spec >"$w/.lavish/cook-spec.html"
  (cd "$w" && PASEO_AGENT_ID=a1 "$S/report.sh" --spec .lavish/cook-spec.html build "#42" "Spec approved.") >/dev/null
  commit "$w" offline.js
  printf 'VERIFY: FAIL\n' >"$w/.context/verify/1/receipt.md"
  (cd "$w" && PASEO_AGENT_ID=a1 "$S/report.sh" --receipt .context/verify/1/receipt.md verify "#42" "Verify failed.") >/dev/null
  status 42
  assert_rc 0
  assert_has "#42 · local · agent a1"
  assert_has "step     verify for"
  assert_has "branch   feat-offline · head $(git -C "$w" rev-parse --short=7 HEAD)"
  assert_has "spec     approved"
  assert_has "verify   FAIL on $(git -C "$w" rev-parse --short=7 HEAD) (attempt 1)"
  assert_has "links    spec http://studio:4387/s/1"
  assert_lacks "resume"
}

test_unknown_ref() {
  status "#9"
  assert_rc 2
  assert_has "No cook build matches #9."
}

test_ready_build_without_agent_is_not_listed() {
  build a1 "#42" feat-offline ready "PR is ready." https://github.com/acme/app/pull/57
  forget_agent local a1
  status
  assert_has "No cook builds are running."
}

test_remote_builds_and_machines_that_do_not_answer() {
  r=$(new_repo app box)
  w=$(worktree "$r" feat-remote box)
  agent box a-remote "#7" blocked "$w"
  event box a-remote "$(date -u +%Y-%m-%dT%H:%M:%SZ)" blocked "#7" "No seed user. Next: reply \"use seed user 3\"" -
  down pi
  MACHINES="local box pi" status
  assert_rc 0
  assert_has "#7"
  assert_has "No seed user."
  assert_has "Not reachable: pi."
}
