---
name: verifier-design
description: Verify that UI changes in <app name> match the approved mockup and the design system - spacing, type, color, states, responsive layout, dark mode and basic accessibility. Use for any change a user can see.
---

# verifier-design

Runs after verifier-browser on the same dev server and session.

## Reference

- The approved spec and mockup: `.lavish/cook-spec.html` or `docs/specs/<ref>.html`.
- Design tokens: <path to Tailwind config, CSS variables or theme file>.
- Shared components: <path>. A new one-off component where a shared one exists is a FAIL.

## Steps

1. For each screen in the mockup, take a screenshot in each state and viewport it shows (`agent-browser set viewport <w> <h>`, `set media dark|light`).
2. Compare each one to the mockup. List each difference as: intended (with the reason from the build) or a defect.
3. Check the tokens: no hard-coded colors, sizes or fonts where a token exists (`git diff` for hex values and px literals in the changed files).
4. Long content: put long text and many items in the UI (from the mockup's state switcher, or test data). Nothing may overflow or overlap.
5. Accessibility basics: every control can be reached and used with the keyboard (`press Tab`), focus is visible, images and icon buttons have labels (`snapshot` shows names), text contrast is readable.

## Result

PASS, FAIL or BLOCKED for each screen, with paired screenshots (mockup and real) and the list of differences.

## Track record
