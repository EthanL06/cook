# cleanup.sh: verdicts, and removal that never loses uncommitted or unpushed work.

# build <id> <ref> <branch> [machine]: a worktree with one pushed commit, its agent and one event. Sets r and w.
build() {
  local m=${4:-local}
  [ -n "${r:-}" ] || r=$(new_repo app "$m")
  w=$(worktree "$r" "$3" "$m")
  commit "$w" "$3.js"
  git -C "$w" push -q origin "$3"
  agent "$m" "$1" "$2" review "$w"
  event "$m" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" review "$2" "PR is open." "https://github.com/acme/app/pull/${2#\#}"
}
cleanup() { run env COOK_MACHINES="${MACHINES:-local}" "$S/cleanup.sh" "$@"; }
line_of() { grep -F -- "$1" <<<"$out"; }
verdict_of() { line_of "$1" | awk '{ print $1 }'; }

test_list_gives_each_build_a_verdict() {
  build a-merged "#1" feat-merged
  pr feat-merged MERGED "$(git -C "$w" rev-parse HEAD)" https://github.com/acme/app/pull/1
  build a-open "#2" feat-open
  pr feat-open OPEN "$(git -C "$w" rev-parse HEAD)" https://github.com/acme/app/pull/2
  build a-named "#3" feat-named
  build a-closed "#4" feat-closed
  pr feat-closed CLOSED "$(git -C "$w" rev-parse HEAD)" https://github.com/acme/app/pull/4
  build a-stale "#5" feat-stale
  rm "$HOME/.local/state/cook/events/a-stale.log"
  event local a-stale 2020-01-01T00:00:00Z review "#5" "PR is open." -
  build a-dirty "#6" feat-dirty
  pr feat-dirty MERGED "$(git -C "$w" rev-parse HEAD)"
  echo wip >"$w/wip.js"
  build a-ahead "#7" feat-ahead
  pr feat-ahead MERGED "$(git -C "$w" rev-parse HEAD)"
  commit "$w" more.js
  build a-gonebranch "#8" feat-gonebranch
  pr feat-gonebranch MERGED "$(git -C "$w" rev-parse HEAD)" https://github.com/acme/app/pull/8
  git -C "$w" push -q origin --delete feat-gonebranch
  git -C "$w" fetch -q --prune origin
  cleanup list 3
  assert_rc 0
  assert_eq "$(verdict_of local:a-merged:)" target merged
  assert_eq "$(verdict_of local:a-open:)" keep open
  assert_eq "$(verdict_of local:a-named:)" target named
  line_of local:a-named: | grep -q "named, no PR" || fail "named reason"
  assert_eq "$(verdict_of local:a-closed:)" suggest closed
  assert_eq "$(verdict_of local:a-stale:)" suggest stale
  line_of local:a-stale: | grep -q "no activity for" || fail "stale reason"
  assert_eq "$(verdict_of local:a-dirty:)" skip dirty
  line_of local:a-dirty: | grep -q "1 uncommitted file(s)" || fail "dirty reason"
  assert_eq "$(verdict_of local:a-ahead:)" skip ahead
  line_of local:a-ahead: | grep -q "1 unpushed commit(s)" || fail "ahead reason"
  assert_eq "$(verdict_of local:a-gonebranch:)" target "merged, remote branch deleted"
  assert_has "MACHINE  local            8 cook builds"
}

test_run_keeps_uncommitted_work() {
  build a1 "#42" feat-offline
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  (cd "$w" && PASEO_AGENT_ID=a1 "$S/report.sh" ready "#42" "PR is ready." https://github.com/acme/app/pull/42) >/dev/null
  echo "half done" >"$w/sync.js"
  cleanup run "local:a1:#42"
  assert_rc 2
  assert_has "#42 local: skipped, 1 uncommitted file(s) in $w"
  assert_eq "$(cat "$w/sync.js")" "half done" "the uncommitted file"
  git -C "$r" show-ref -q --verify refs/heads/feat-offline || fail "the local branch is gone"
  assert_eq "$(agent_field local a1 .archived)" false "agent archived"
  assert_file "$HOME/.local/state/cook/events/a1.log"
  assert_file "$HOME/.local/state/cook/runs/app-42.json"
  assert_not_called paseo "archive"
}

test_run_keeps_unpushed_commits() {
  build a1 "#42" feat-offline
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  commit "$w" fix.js
  sha=$(git -C "$w" rev-parse HEAD)
  cleanup run "local:a1:#42"
  assert_rc 2
  assert_has "skipped, 1 unpushed commit(s) in $w"
  assert_eq "$(git -C "$w" rev-parse HEAD)" "$sha" "worktree head"
  assert_eq "$(git -C "$r" rev-parse feat-offline)" "$sha" "branch"
  assert_eq "$(agent_field local a1 .archived)" false "agent archived"
}

test_run_removes_a_merged_build_and_only_that_build() {
  build a1 "#42" feat-offline
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  (cd "$w" && PASEO_AGENT_ID=a1 "$S/report.sh" ready "#42" "PR is ready." https://github.com/acme/app/pull/42) >/dev/null
  mkdir -p "$TMPDIR/cook-watch" && touch "$TMPDIR/cook-watch/a1"
  keep=$w
  build a2 "#43" feat-other
  other=$w
  w=$keep
  cleanup run "local:a1:#42"
  assert_rc 0
  assert_has "#42 local: cleaned up."
  assert_no_file "$w"
  [ -z "$(git -C "$r" branch --list feat-offline)" ] || fail "local branch is still there"
  git -C "$r" ls-remote --exit-code --heads origin feat-offline >/dev/null || fail "the remote branch was deleted"
  assert_eq "$(agent_field local a1 .archived)" true "agent archived"
  assert_no_file "$HOME/.local/state/cook/events/a1.log"
  assert_no_file "$HOME/.local/state/cook/runs/app-42.json"
  assert_no_file "$HOME/.local/state/cook/runs/app-42"
  assert_no_file "$TMPDIR/cook-watch/a1"
  assert_file "$other/feat-other.js"
  assert_eq "$(agent_field local a2 .archived)" false "other agent"
}

test_run_stops_processes_in_the_worktree() {
  build a1 "#42" feat-offline
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  (cd "$w" && exec sleep 300) &
  pid=$!
  (cd "$T" && exec sleep 300) &
  other=$!
  sleep 1
  cleanup run "local:a1:#42"
  assert_rc 0
  assert_has "processes stopped: $pid"
  sleep 1
  kill -0 "$pid" 2>/dev/null && fail "the process in the worktree still runs"
  kill -0 "$other" 2>/dev/null || fail "a process outside the worktree was stopped"
  kill "$other"
}

test_resumed_build_is_found_and_all_its_agents_go() {
  build a-old "#42" feat-offline
  (cd "$w" && PASEO_AGENT_ID=a-old "$S/report.sh" build "#42" "Spec approved.") >/dev/null
  agent local a-new "#42" verify "$w"
  (cd "$w" && PASEO_AGENT_ID=a-new "$S/report.sh" verify "#42" "Resumed at verify.") >/dev/null
  jq '.labels["cook-step"] = "resumed"' "$STUB_STATE/paseo/local/a-old.json" >"$T/a.json" && mv "$T/a.json" "$STUB_STATE/paseo/local/a-old.json"
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  cleanup list
  assert_has "local:a-new:#42"
  assert_lacks "local:a-old:#42"
  cleanup run "local:a-new:#42"
  assert_rc 0
  assert_eq "$(agent_field local a-old .archived)" true "old agent archived"
  assert_eq "$(agent_field local a-new .archived)" true "new agent archived"
  assert_no_file "$HOME/.local/state/cook/events/a-old.log"
  assert_no_file "$HOME/.local/state/cook/events/a-new.log"
}

test_build_whose_agent_is_gone_is_listed_and_removed() {
  build a1 "#42" feat-offline
  (cd "$w" && PASEO_AGENT_ID=a1 "$S/report.sh" verify "#42" "Verify started.") >/dev/null
  forget_agent local a1
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  cleanup list
  assert_eq "$(verdict_of local:a1:)" target "verdict"
  cleanup run "local:a1:#42"
  assert_rc 0
  assert_no_file "$w"
  assert_no_file "$HOME/.local/state/cook/runs/app-42.json"
}

test_unreachable_machine_is_skipped() {
  r=""
  build a1 "#42" feat-offline box
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  down box
  MACHINES="local box" cleanup list
  assert_rc 0
  assert_has "MACHINE  box              does not answer"
  MACHINES="local box" cleanup run "box:a1:#42"
  assert_rc 2
  assert_has "#42 box: skipped, box does not answer"
  assert_file "$w"
  assert_eq "$(agent_field box a1 .archived)" false "agent archived"
}

test_remote_build_is_removed_over_ssh() {
  r=""
  build a1 "#42" feat-offline box
  pr feat-offline MERGED "$(git -C "$w" rev-parse HEAD)"
  MACHINES="box" cleanup run "box:a1:#42"
  assert_rc 0
  assert_no_file "$w"
  assert_eq "$(agent_field box a1 .archived)" true "agent archived"
}

test_bad_arguments() {
  cleanup
  assert_rc 1
  cleanup run
  assert_rc 1
  cleanup run "nonsense"
  assert_rc 2
  assert_has "bad build string"
}
