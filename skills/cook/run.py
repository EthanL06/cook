#!/usr/bin/env python3
"""The run state of each build, so that a build can resume after a crash.

Usage: run.py update [--check] --step <step> --ref <ref> --agent <id> --text <text> [--url <url>]
                     [--brief <file>] [--spec <file>] [--receipt <file>]
       run.py get <ref or key> [field]
       run.py list
       run.py remove <ref or key>
       run.py pick <ref, key or agent id>     reads "<machine><TAB><state>" lines on stdin
       run.py brief [--head <sha>] [--dirty <n>]  reads one state on stdin, prints the resume brief

report.sh calls update in the build agent's worktree. One file per build:
$COOK_STATE/runs/<key>.json (one line of JSON, replaced atomically), and the folder
$COOK_STATE/runs/<key>/ with copies of the brief, the approved spec and each verify
receipt, so they stay when the worktree is gone. <key> is <repo name>-<ref>.

--brief <file>    the build brief (the first prompt of the build agent).
--spec <file>     the approved spec. Give it once, with the report that starts the build.
                  After that, the spec stays approved: a new spec or a plan step is refused.
--receipt <file>  a /cook-verify receipt. Its first line "VERIFY: PASS|FAIL|BLOCKED" is the verdict.
--check           validate only. Nothing is written.

Exit codes: 0 done, 1 bad arguments, 2 no such run, 3 more than one run matches,
5 refused because the spec is approved already.
"""
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

STEPS = ("plan", "build", "verify", "review", "learn", "blocked", "ready")
STATE = pathlib.Path(os.environ.get("COOK_STATE") or pathlib.Path.home() / ".local/state/cook")
RUNS = STATE / "runs"
HISTORY = 10


class Refused(Exception):
    pass


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git(*args, cwd=None):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def safe(text):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", text.lstrip("#")).strip("-") or "build"


def repo_facts():
    top = git("rev-parse", "--show-toplevel")
    if not top:
        return {}
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    main = common[:-5] if common.endswith("/.git") else top
    origin = git("config", "--get", "remote.origin.url")
    name = re.sub(r"\.git$", "", origin.rstrip("/").split("/")[-1].split(":")[-1]) if origin else ""
    return {"cwd": top, "repo": main, "origin": origin, "name": name or os.path.basename(main),
            "branch": git("branch", "--show-current"), "head": git("rev-parse", "HEAD")}


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def copy_atomic(src, dst):
    write_atomic(dst, pathlib.Path(src).read_bytes())


def save(state):
    write_atomic(RUNS / f"{state['key']}.json", (json.dumps(state, sort_keys=True) + "\n").encode())


def runs():
    out = []
    for p in sorted(RUNS.glob("*.json")):
        try:
            out.append(json.loads(p.read_text()))
        except (OSError, ValueError):
            continue
    return out


def matches(state, want):
    w = want.lstrip("#")
    return want == state.get("key") or w == str(state.get("ref", "")).lstrip("#") \
        or (len(want) >= 7 and any(a.startswith(want) for a in state.get("agents", [])))


def brief_facts(text):
    facts = {}
    m = re.search(r"^Issue: (\S+) (.+)$", text, re.M)
    if m:
        facts["title"] = m.group(2).strip()
    m = re.search(r"^Branch: \S+\s+Base: (\S+)", text, re.M)
    if m:
        facts["base"] = m.group(1)
    m = re.search(r"^Machine: (\S+)", text, re.M)
    if m:
        facts["machine"] = m.group(1)
    return facts


def verdict_of(path):
    try:
        first = pathlib.Path(path).read_text().lstrip().splitlines()[0]
    except (OSError, IndexError):
        raise SystemExit(f"cannot read the receipt {path}")
    m = re.match(r"VERIFY:\s*(PASS|FAIL|BLOCKED)\b", first)
    if not m:
        raise SystemExit(f"{path} is not a /cook-verify receipt: its first line must be 'VERIFY: PASS', 'FAIL' or 'BLOCKED'")
    return m.group(1)


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def update(o):
    step, ref = o["step"], o["ref"]
    if step not in STEPS:
        raise SystemExit(f"unknown step {step}")
    facts = repo_facts()
    key = f"{safe(facts['name'])}-{safe(ref)}" if facts else safe(ref)
    path = RUNS / f"{key}.json"
    state = json.loads(path.read_text()) if path.exists() else {
        "version": 1, "key": key, "ref": ref, "started": now(), "agents": [], "verify_history": []}
    spec = state.get("spec") or {}
    if spec.get("approved") and step == "plan":
        raise Refused(f"the spec of {ref} is approved ({spec['approved']}): the plan step is done. "
                      f"Continue from {state.get('resume_step', 'build')}.")
    if o.get("spec"):
        if step == "plan":
            raise SystemExit("--spec is for the approved spec: give it with the report that starts the build")
        if not os.path.isfile(o["spec"]):
            raise SystemExit(f"no spec file: {o['spec']}")
        if spec.get("approved") and spec.get("sha256") != sha256(o["spec"]):
            raise Refused(f"the spec of {ref} is approved already ({spec['copy']}). A changed spec needs a new build, "
                          "or the user's go-ahead to remove this run state.")
    verdict = verdict_of(o["receipt"]) if o.get("receipt") else None
    for f in ("brief",):
        if o.get(f) and not os.path.isfile(o[f]):
            raise SystemExit(f"no {f} file: {o[f]}")
    if o.get("check"):
        return

    files = RUNS / key
    t = now()
    if o.get("brief"):
        copy_atomic(o["brief"], files / "brief.md")
        state["brief"] = str(files / "brief.md")
        state.update(brief_facts((files / "brief.md").read_text()))
    if o.get("spec") and not spec.get("approved"):
        ext = pathlib.Path(o["spec"]).suffix or ".html"
        copy_atomic(o["spec"], files / f"spec{ext}")
        state["spec"] = {"source": os.path.abspath(o["spec"]), "copy": str(files / f"spec{ext}"),
                         "sha256": sha256(o["spec"]), "approved": t, "url": state.get("spec_url", "")}
    if verdict:
        n = (state.get("verify") or {}).get("attempts", 0) + 1
        copy_atomic(o["receipt"], files / f"receipt-{n}.md")
        state["verify"] = {"verdict": verdict, "receipt": os.path.abspath(o["receipt"]),
                           "copy": str(files / f"receipt-{n}.md"), "head": facts.get("head", ""), "at": t, "attempts": n}
        state["verify_history"] = (state.get("verify_history", []) + [
            {k: state["verify"][k] for k in ("verdict", "copy", "head", "at")}])[-HISTORY:]

    for k in ("cwd", "repo", "origin", "branch", "head"):
        if facts.get(k):
            state[k] = facts[k]
    if o["agent"] not in state["agents"]:
        state["agents"].append(o["agent"])
    url = o.get("url") or ""
    if step == "plan" and url:
        state["spec_url"] = url
    if re.search(r"/pull/\d+$", url):
        state["pr"] = url
    if step != "blocked":
        state["resume_step"] = step
    state.setdefault("resume_step", "plan")
    state.update({"step": step, "agent_id": o["agent"], "text": o["text"], "url": url, "updated": t,
                  "host": os.uname().nodename})
    state.setdefault("machine", os.uname().nodename)
    save(state)


def lookup(state, field):
    cur = state
    for part in field.split("."):
        cur = cur.get(part) if isinstance(cur, dict) else None
    return cur


def pick(want, lines):
    hits = []
    for line in lines:
        m, _, raw = line.partition("\t")
        try:
            s = json.loads(raw)
        except ValueError:
            continue
        if matches(s, want):
            hits.append((m, s))
    if not hits:
        print(f"no run state matches {want}", file=sys.stderr)
        return 2
    if len(hits) > 1:
        print(f"more than one build matches {want}. Name one by its key:", file=sys.stderr)
        for m, s in hits:
            print(f"  {s['key']}  ({s.get('ref')} on {m}, {s.get('repo', '?')})", file=sys.stderr)
        return 3
    m, s = hits[0]
    print(f"{m}\t{json.dumps(s, sort_keys=True)}")
    return 0


SECTIONS = {"plan": "4 (spec)", "build": "5 (build)", "verify": "6 (verify)", "pr": "7 (pull request)",
            "review": "8 (review loop)", "learn": "9 (learn)", "ready": "10 (done)"}


def where(s, head):
    """The step to continue from, and the SKILL.md section for it."""
    step = s.get("resume_step") or "plan"
    if (s.get("spec") or {}).get("approved") and step == "plan":
        step = "build"
    v = s.get("verify") or {}
    if step == "verify" and v.get("verdict") == "PASS" and v.get("head") == head:
        step = "pr"
    return step, SECTIONS[step]


def brief(argv, state):
    opt = dict(zip(argv[::2], argv[1::2]))
    head = opt.get("--head") or state.get("head", "")
    dirty = opt.get("--dirty", "0")
    step, section = where(state, head)
    spec = state.get("spec") or {}
    v = state.get("verify") or {}
    tpl = pathlib.Path(__file__).with_name("templates") / "resume.md"
    if spec.get("approved"):
        spec_text = (f"Approved on {spec['approved']}. The copy is {spec['copy']} (from {spec['source']}"
                     f"{', ' + spec['url'] if spec.get('url') else ''}). Build exactly this spec. Do not change it, "
                     "and do not ask for approval again.")
    elif state.get("spec_url"):
        spec_text = f"Not approved yet. The last draft is {state['spec_url']}. Continue the spec loop from there."
    else:
        spec_text = "Not written yet."
    if v:
        verify_text = (f"{v['verdict']} on {v['head'][:7] or '?'} at {v['at']}, attempt {v['attempts']}. "
                       f"Receipt: {v['copy']}.")
        if v["verdict"] != "PASS":
            verify_text += " Read it before you change code. Fix the cause it names, then run /cook-verify again."
    else:
        verify_text = "Not run yet."
    if dirty != "0":
        tree = (f"{dirty} uncommitted file(s) from before the stop. The user knows. Keep them: read the diff, "
                "and use or commit what belongs to this build. Never discard them.")
    else:
        tree = "Clean."
    values = {
        "ref": state.get("ref", ""), "title": state.get("title", ""), "step": step, "section": section,
        "step_report": step if step in STEPS else "verify",
        "last_step": state.get("step", ""), "last_text": state.get("text", ""), "last_url": state.get("url") or "-",
        "branch": state.get("branch", ""), "base": state.get("base", "?"), "cwd": state.get("cwd", ""),
        "head": head, "brief": state.get("brief") or "none", "spec": spec_text, "verify": verify_text,
        "pr": state.get("pr") or "none yet", "tree": tree, "key": state.get("key", ""),
    }
    text = tpl.read_text()
    for k, val in values.items():
        text = text.replace("{" + k + "}", str(val))
    print(text, end="")


def parse_update(argv):
    o, i = {}, 0
    while i < len(argv):
        a = argv[i]
        if a == "--check":
            o["check"] = True
            i += 1
        elif a.startswith("--") and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            raise SystemExit(f"unknown argument: {a}")
    for k in ("step", "ref", "agent", "text"):
        if not o.get(k):
            raise SystemExit(f"update needs --{k}")
    return o


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
    try:
        if cmd == "update":
            update(parse_update(rest))
            return 0
    except Refused as e:
        print(f"refused: {e}", file=sys.stderr)
        return 5
    except SystemExit as e:
        if isinstance(e.code, str):
            print(e.code, file=sys.stderr)
            return 1
        raise
    if cmd == "list":
        for s in sorted(runs(), key=lambda s: s.get("updated", "")):
            print(json.dumps(s, sort_keys=True))
        return 0
    if cmd in ("get", "remove") and rest:
        hits = [s for s in runs() if matches(s, rest[0])]
        if not hits:
            print(f"no run state matches {rest[0]}", file=sys.stderr)
            return 2
        if len(hits) > 1:
            print(f"more than one build matches {rest[0]}: {', '.join(s['key'] for s in hits)}", file=sys.stderr)
            return 3
        s = hits[0]
        if cmd == "remove":
            (RUNS / f"{s['key']}.json").unlink(missing_ok=True)
            shutil.rmtree(RUNS / s["key"], ignore_errors=True)
            return 0
        v = lookup(s, rest[1]) if len(rest) > 1 else s
        if v is None:
            return 2
        print(json.dumps(v, indent=1) if isinstance(v, (dict, list)) else v)
        return 0
    if cmd == "pick" and rest:
        return pick(rest[0], sys.stdin.read().splitlines())
    if cmd == "brief":
        brief(rest, json.loads(sys.stdin.read()))
        return 0
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
