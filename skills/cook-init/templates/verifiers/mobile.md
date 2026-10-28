---
name: verifier-mobile
description: Verify changes to <app name>'s iOS app on the iOS Simulator - screens render, flows work, no red screens or crashes. Use for changes under <apps/mobile/**> that a user can see or touch. Needs macOS with Xcode.
---

# verifier-mobile

## Setup

1. A booted simulator: `xcrun simctl list devices booted`. If none, boot one: `xcrun simctl boot "<iPhone 16>"`.
2. A development build of the worktree under test: <for example `npx expo run:ios --no-bundler` once, then `npx expo start --dev-client --port <port>`>. Save the logs to `$run/`.
3. Open the app: `xcrun simctl launch booted <bundle id>`, or a deep link: `xcrun simctl openurl booted "<scheme>://<path>"`.

## Steps

1. For each screen the claim names, open it with a deep link when the app has one, else by the flow.
2. Screenshot each state: `xcrun simctl io booted screenshot "$run/<claim>-<state>.png"`. For light and dark: `xcrun simctl ui booted appearance light|dark`.
3. For flows with taps, use the flow runner the project set up (<for example Maestro: `maestro test .maestro/<flow>.yaml`>). With no runner, mark the tap part BLOCKED and say so.
4. Read the bundler and device logs (`xcrun simctl spawn booted log show --last 5m --predicate 'process == "<app>"'`) for red screens, errors and crashes made during the run.

## Teardown

Stop the bundler you started. Leave the simulator booted.

## Result

PASS, FAIL or BLOCKED for each claim, with screenshots and log paths.

## Track record
