# The hub side: watch.sh, doctor.sh and machines.py.

# bounded <cmd>: runs it, and stops it after 30 seconds, so a watch that never ends fails the test instead of hanging.
bounded() {
  "$@" &
  local p=$! k r
  (sleep 30; kill "$p" 2>/dev/null) >/dev/null 2>&1 &
  k=$!
  wait "$p"; r=$?
  kill "$k" 2>/dev/null
  return "$r"
}
watch() { export COOK_WATCH_INTERVAL=0 COOK_MACHINES="local box"; run bounded "$S/watch.sh" "$@"; }

# Everything doctor needs for the defaults is there.
all_tools() {
  tool claude agent-browser no-mistakes
  mkdir -p "$HOME/.agent-browser/browsers/chrome-130" "$STUB_STATE/npx"
  touch "$STUB_STATE/npx/cached-lavish-axi"
}
doctor() { run "$S/doctor.sh" "$@"; }

test_watch_prints_each_event_once_and_ends_on_merge() {
  event local a1 2026-10-28T10:00:00Z plan "#42" "Spec v1 is ready." "http://studio:4387/s/1"
  event local a1 2026-10-28T11:00:00Z review "#42" "PR is open." https://github.com/acme/app/pull/57
  r=$(new_repo app box)
  event box b1 2026-10-28T10:30:00Z blocked "#43" "No seed user. Next: reply \"use seed user 3\"" -
  event box b1 2026-10-28T10:40:00Z review "#43" "PR is open." https://github.com/acme/app/pull/58
  pr feat-a MERGED aaa https://github.com/acme/app/pull/57
  pr feat-b CLOSED bbb https://github.com/acme/app/pull/58
  watch "local:a1:#42" "box:b1:#43"
  assert_rc 0
  assert_has "local COOK EVENT 2026-10-28T10:00:00Z plan #42 | Spec v1 is ready. | http://studio:4387/s/1"
  assert_has "box COOK EVENT 2026-10-28T10:30:00Z blocked #43 | No seed user."
  assert_has "merged #42 | PR merged. Ready to clean up. | https://github.com/acme/app/pull/57"
  assert_has "closed #43 | PR closed without a merge."
  watch "local:a1:#42" "box:b1:#43"
  assert_rc 0
  assert_eq "$out" "" "output of the second watch"
  event local a1 2026-10-28T12:00:00Z ready "#42" "PR is ready." https://github.com/acme/app/pull/57
  watch "local:a1:#42"
  assert_eq "$out" "local COOK EVENT 2026-10-28T12:00:00Z ready #42 | PR is ready. | https://github.com/acme/app/pull/57" "new line only"
}

test_watch_allows_permission_requests() {
  event local a1-agent 2026-10-28T10:00:00Z review "#42" "PR is open." https://github.com/acme/app/pull/57
  pr feat-a MERGED aaa https://github.com/acme/app/pull/57
  mkdir -p "$STUB_STATE/paseo/local"
  echo '[{"id": "req-1", "agentId": "a1-agent", "name": "Bash"}, {"id": "req-2", "agentId": "zz-other", "name": "Bash"}]' \
    >"$STUB_STATE/paseo/local/permits.json"
  watch "local:a1-agent:#42"
  assert_rc 0
  assert_has "permission #42 | allowed Bash (req-1)"
  assert_called paseo "permit allow a1-agent req-1"
  assert_not_called paseo "req-2"
}

test_watch_needs_builds() {
  run "$S/watch.sh"
  assert_rc 1
}

test_doctor_passes_with_every_tool_and_remembers_it() {
  all_tools
  doctor
  assert_rc 0
  assert_has "Ready."
  assert_lacks MISSING
  doctor --quick
  assert_rc 0
  assert_eq "$out" "doctor: ok (checked in the last 24 hours)" "quick run"
}

test_doctor_quick_checks_again_after_cook_md_changes() {
  all_tools
  r=$(new_repo app)
  cookmd "$r" "tracker: github"
  cd "$r" || fail cd
  doctor
  assert_rc 0
  cookmd "$r" "tracker: linear
linear_team: ENG"
  doctor --quick
  assert_rc 1
  assert_has "MISSING  LINEAR_API_KEY"
  assert_has "MISSING  linear-sdk-axi"
}

test_doctor_lists_missing_tools_and_fixes_only_on_yes() {
  all_tools
  untool jq no-mistakes
  doctor
  assert_rc 1
  assert_has "MISSING  jq                     brew install jq"
  assert_has "Run doctor.sh --fix to install the missing tools."
  doctor --fix
  assert_rc 1
  assert_has "Not run. Ask the user, then run: doctor.sh --fix --yes"
  assert_not_called brew install
  doctor --fix --yes
  assert_has "> brew install jq"
  assert_called brew "install jq"
  assert_has "no-mistakes"
}

test_doctor_never_runs_steps_that_need_an_account() {
  all_tools
  touch "$STUB_STATE/gh/no-auth" 2>/dev/null || { mkdir -p "$STUB_STATE/gh"; touch "$STUB_STATE/gh/no-auth"; }
  untool claude
  doctor --fix --yes
  assert_rc 1
  assert_has "Do these yourself"
  assert_has "gh sign-in: run: gh auth login"
  assert_has "claude or codex: install one and sign in"
  assert_not_called gh "auth login"
}

test_doctor_checks_what_the_project_uses() {
  all_tools
  r=$(new_repo app)
  cookmd "$r" "review: greptile
browser: playwright-axi
ui_refs: mobbin
notify: off"
  cd "$r" || fail cd
  doctor
  assert_rc 1
  assert_has "Review loop (greptile)"
  assert_has "MISSING  Greptile loop skill"
  assert_has "MISSING  playwright-axi"
  assert_has "MISSING  mobbin-axi"
  assert_lacks "phone pushes"
  mkdir -p "$HOME/.agents/skills/greptile-loop"
  touch "$STUB_STATE/npx/cached-playwright-axi" "$STUB_STATE/npx/cached-mobbin-axi"
  echo "authenticated: true" >"$STUB_STATE/npx/out-mobbin-axi"
  doctor
  assert_rc 0
}

tailnet() {
  cat >"$STUB_STATE/tailscale.json" <<'EOF'
{"Self": {"DNSName": "studio.tail1.ts.net.", "HostName": "Studio", "TailscaleIPs": ["100.64.0.1"], "OS": "macOS"},
 "Peer": {
  "n1": {"DNSName": "box.tail1.ts.net.", "HostName": "box", "TailscaleIPs": ["100.64.0.2"], "OS": "linux", "Online": true},
  "n2": {"DNSName": "pi.tail1.ts.net.", "HostName": "pi", "TailscaleIPs": ["100.64.0.3"], "OS": "linux", "Online": false},
  "n3": {"DNSName": "gamer.tail1.ts.net.", "HostName": "gamer", "TailscaleIPs": ["100.64.0.4"], "OS": "windows", "Online": true}}}
EOF
}
skill_on() { mkdir -p "$(home_of "$1")/.agents/skills/cook"; touch "$(home_of "$1")/.agents/skills/cook/SKILL.md"; }

test_machines_without_tailscale_is_this_machine_only() {
  untool tailscale
  run python3 -I "$S/machines.py" --json
  assert_rc 0
  assert_eq "$(jq -r 'map(.name) | join(",")' <<<"$out")" local "machines"
  assert_eq "$(env -u COOK_MACHINES bash -c ". '$S/lib.sh'; cook_machines")" local "cook_machines"
}

test_machines_checks_each_peer() {
  tailnet
  tool node claude
  skill_on local
  run python3 -I "$S/machines.py" --json
  assert_rc 0
  assert_eq "$(jq -r 'map(.name) | join(",")' <<<"$out")" "studio,box,pi" "machines (no windows)"
  assert_eq "$(jq -r '.[] | select(.name == "studio") | .ready' <<<"$out")" true "this machine"
  assert_eq "$(jq -r '.[] | select(.name == "box") | .missing | join(",")' <<<"$out")" "cook skill" "box"
  assert_eq "$(jq -r '.[] | select(.name == "pi") | .missing | join(",")' <<<"$out")" offline "pi"
  assert_eq "$(jq -r '.[] | select(.name == "box") | .paseoHost' <<<"$out")" ssh://box "paseo host"
  skill_on box
  new_repo app box >/dev/null
  run python3 -I "$S/machines.py" --origin https://github.com/acme/app.git --json
  assert_eq "$(jq -r '.[] | select(.name == "box") | .missing | join(",")' <<<"$out")" "" "box with the skill"
  assert_eq "$(jq -r '.[] | select(.name == "box") | .repo' <<<"$out")" "$STUB_HOSTS/box/Developer/app" "checkout on box"
  assert_eq "$(jq -r '.[] | select(.name == "studio") | .missing | join(",")' <<<"$out")" "checkout of acme/app" "studio has no checkout"
  assert_eq "$(env -u COOK_MACHINES bash -c ". '$S/lib.sh'; cook_machines" | tr '\n' ' ')" "local box " "cook_machines"
  down box
  run python3 -I "$S/machines.py" --json
  assert_eq "$(jq -r '.[] | select(.name == "box") | .missing | join(",")' <<<"$out")" ssh "box down"
  run python3 -I "$S/machines.py"
  assert_has "box                  linux         missing: ssh"
}
