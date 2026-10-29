# shellcheck shell=bash disable=SC2154 # out, rc and the sandbox paths come from tests/lib.sh
# config.py, and how tracker.sh, notify.sh and doctor.sh act on a missing or invalid .agents/cook.md.

C() { python3 -I "$S/config.py" "$@"; }

test_missing_file_gives_the_defaults_and_path_says_so() {
  r=$(new_repo app)
  cd "$r" || fail cd
  run C get base
  assert_rc 0
  assert_eq "$out" main "default base"
  run C get tracker
  assert_eq "$out" github "default tracker"
  run C get linear_team
  assert_rc 2
  assert_has "no cook.md at $r/.agents/cook.md: run /cook-init"
  run C get linear_team ENG
  assert_rc 0
  assert_eq "$out" ENG "default from the command line"
  run C path
  assert_rc 2
  run C check
  assert_rc 2
}

test_reads_values_lists_and_nested_keys() {
  r=$(new_repo app)
  cookmd "$r" 'base: develop          # PRs go here
tracker: linear
linear_team: "ENG"
branch: "{user}/{id}-{slug}"
branch_max: 34
notify: off
commands:
  dev: pnpm dev   # web on :3000
  test: "pnpm test # not a comment"
deploy_steps:
  - migrations/**
  - wrangler.jsonc
verifiers: [browser, api]'
  cd "$r" || fail cd
  run C check
  assert_rc 0
  assert_eq "$(C get base)" develop base
  assert_eq "$(C get branch)" "{user}/{id}-{slug}" branch
  assert_eq "$(C get notify)" off notify
  assert_eq "$(C get commands.dev)" "pnpm dev" commands.dev
  assert_eq "$(C get commands.test)" "pnpm test # not a comment" commands.test
  assert_eq "$(C get deploy_steps | tr '\n' ' ')" "migrations/** wrangler.jsonc " deploy_steps
  assert_eq "$(C get verifiers | tr '\n' ' ')" "browser api " verifiers
  assert_eq "$(C get commands | jq -r .dev)" "pnpm dev" "commands as JSON"
  assert_eq "$(C get review)" no-mistakes "default for a key that is not set"
  run C get commands.nothing
  assert_rc 3
}

test_a_worktree_reads_the_main_checkout() {
  r=$(new_repo app)
  cookmd "$r" "base: release"
  w=$(worktree "$r" feat-x)
  cd "$w" || fail cd
  assert_eq "$(C get base)" release "base from the worktree"
  assert_eq "$(C path)" "$r/.agents/cook.md" path
}

test_cook_config_reads_another_file() {
  printf -- '---\ntracker: none\n---\n' >"$T/draft.md"
  assert_eq "$(COOK_CONFIG="$T/draft.md" python3 -I "$S/config.py" get tracker)" none tracker
}

test_bad_values_are_listed_and_stop_get() {
  r=$(new_repo app)
  cookmd "$r" 'base: "my branch"
tracker: jira
review: coderabbit
browser: safari
specs: cloud
notify: maybe
ui_refs: dribbble
branch: "{type}-{name}"
commit: "{type}: fix"
branch_max: short
verifiers: browser
colour: blue'
  cd "$r" || fail cd
  run C check
  assert_rc 4
  assert_has "$r/.agents/cook.md is not valid:"
  assert_has "base: 'my branch' is not a branch name"
  assert_has "tracker: 'jira' is not one of github, linear, none"
  assert_has "review: 'coderabbit' is not one of no-mistakes, greptile, none"
  assert_has "browser: 'safari' is not one of"
  assert_has "specs: 'cloud' is not one of local, committed"
  assert_has "notify: 'maybe' is not one of on, off"
  assert_has "ui_refs: 'dribbble' is not one of mobbin, none"
  assert_has "branch: unknown placeholder {name}"
  assert_has "commit: '{type}: fix' needs {summary}"
  assert_has "branch_max: 'short' is not a number"
  assert_has "verifiers: must be a list"
  assert_has "colour: not a cook.md field"
  run C get base
  assert_rc 4
  run C json
  assert_rc 4
}

test_linear_needs_a_team() {
  r=$(new_repo app)
  cookmd "$r" "tracker: linear"
  cd "$r" || fail cd
  run C check
  assert_rc 4
  assert_has "linear_team: tracker is linear"
}

test_broken_yaml_gives_the_line() {
  r=$(new_repo app)
  cd "$r" || fail cd
  mkdir -p .agents
  printf -- '---\nbase: main\ntracker github\nbranch: "{type}-{slug}\nverifiers: [browser, api\n\tcommands: x\n  - orphan\nbase: other\n---\n' >.agents/cook.md
  run C check
  assert_rc 4
  assert_has "line 3: expected 'key: value': tracker github"
  assert_has "line 4: the quote is not closed"
  assert_has "line 5: the list is not closed"
  assert_has "line 6: indent with spaces, not tabs"
  assert_has "line 7: an indented line must be under a key"
  assert_has "line 8: base is set twice"
  run C get base
  assert_rc 4
}

test_header_must_open_and_close() {
  r=$(new_repo app)
  cd "$r" || fail cd
  mkdir -p .agents
  printf '# Project\n\nbase: main\n' >.agents/cook.md
  run C check
  assert_rc 4
  assert_has "line 1: the file must start with a YAML header"
  printf -- '---\nbase: main\n\n# Project\n' >.agents/cook.md
  run C check
  assert_rc 4
  assert_has "the YAML header has no closing --- line"
}

test_tracker_stops_on_an_invalid_config() {
  r=$(new_repo app)
  cookmd "$r" "tracker: jira"
  cd "$r" || fail cd
  run "$S/tracker.sh" view "#42"
  assert_rc 4
  assert_has "tracker: 'jira' is not one of"
  assert_not_called gh "issue view"
}

test_tracker_none_and_github() {
  r=$(new_repo app)
  cd "$r" || fail cd
  cookmd "$r" "tracker: none"
  run "$S/tracker.sh" comment "#42" /dev/null
  assert_rc 0
  assert_has "tracker is none: nothing to do"
  run "$S/tracker.sh" url csv-export
  assert_rc 0
  assert_eq "$out" "" "url with tracker none"
  cookmd "$r" "tracker: github"
  echo body >"$T/body.md"
  run "$S/tracker.sh" create "Add CSV export" "$T/body.md"
  assert_rc 0
  assert_eq "$out" "#42" "new ref"
  run "$S/tracker.sh" state 42 in-review
  assert_rc 0
  assert_called gh "issue edit 42 --add-label cook:in-review --remove-label cook:in-progress"
  touch "$STUB_STATE/gh/fail"
  run "$S/tracker.sh" view "#42"
  assert_rc 2
}

test_notify_follows_the_config_and_the_settings() {
  r=$(new_repo app)
  cd "$r" || fail cd
  run "$S/notify.sh" blocked "#42" "Need a seed user."
  assert_rc 3
  assert_has "not sent: no NOTIFY in $HOME/.config/cook/notify.env"
  mkdir -p "$HOME/.config/cook"
  printf 'NOTIFY=ntfy\nNTFY_TOPIC=cook-test-topic\n' >"$HOME/.config/cook/notify.env"
  run env COOK_NOTIFY_DRY_RUN=1 "$S/notify.sh" blocked "#42" "Need a seed user." https://x/1
  assert_rc 0
  assert_has "title=Blocked: needs you - #42"
  run "$S/notify.sh" ready "#42" "PR is ready." https://github.com/acme/app/pull/57
  assert_rc 0
  assert_called curl "Click: https://github.com/acme/app/pull/57"
  assert_called curl "https://ntfy.sh/cook-test-topic"
  echo '{"error":"forbidden"}' >"$STUB_STATE/curl-response"
  run "$S/notify.sh" ready "#42" "PR is ready."
  assert_rc 4
  cookmd "$r" "notify: off"
  run "$S/notify.sh" ready "#42" "PR is ready."
  assert_rc 0
  assert_has "not sent: notify is off in cook.md"
}

test_doctor_reports_an_invalid_config() {
  r=$(new_repo app)
  cookmd "$r" 'tracker: jira
review none'
  cd "$r" || fail cd
  run "$S/doctor.sh"
  assert_rc 1
  assert_has "MISSING  cook.md"
  assert_has "line 3: expected 'key: value': review none"
}
