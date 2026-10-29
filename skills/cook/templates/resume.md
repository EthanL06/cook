COOK RESUME - read the cook skill. This build stopped before it was done. Continue it from step {section}. Do not do the steps before it again.

Issue: {ref} {title}
Branch: {branch}   Base: {base}
Worktree: {cwd}
Head: {head}
Run state: {key} (read it with: $S/run.py get {key})
Original brief: {brief}

Last report: {last_step} | {last_text} | {last_url}
Continue at: {step}
Spec: {spec}
Last verification: {verify}
PR: {pr}
Worktree changes: {tree}

First, report that you continue: $S/report.sh {step_report} {ref} "Resumed at {step}." Then:
- Read the original brief. Its intake answers still hold.
- Check the commits on the branch (git log origin/{base}..HEAD) and, if there is a PR, its comments. Do not redo work that is in them.
- Verification needs fresh evidence. Never reuse a PASS from before a code change.
