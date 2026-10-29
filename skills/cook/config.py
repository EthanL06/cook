#!/usr/bin/env python3
"""Read the YAML header of a project's .agents/cook.md.

Usage: config.py [--repo <dir>] get <key> [default]
       config.py [--repo <dir>] json
       config.py [--repo <dir>] path
       config.py [--repo <dir>] check

<key> can be nested with dots, for example commands.dev.
The header supports the small YAML subset that cook.md uses: scalars,
quoted strings, inline lists ([a, b]), block lists (- a) and one level
of nested maps. A full YAML parser is not a dependency on purpose.

The file is read from the main checkout, so a build in a worktree reads
the same config as the repo it came from. COOK_CONFIG=<file> reads another
file instead, for example a draft that cook-init has not written yet.

check prints each problem in the header with its line number: broken YAML
and values that cook does not know. get and json stop on the same problems,
so a build never runs on a config that cook reads wrong.

Exit codes: 0 found, 1 bad arguments, 2 no cook.md, 3 key not set and no default,
4 cook.md is not valid.
"""
import json
import os
import re
import subprocess
import sys

DEFAULTS = {
    "base": "main",
    "tracker": "github",
    "branch": "{type}-{slug}",
    "commit": "{type}: {summary}",
    "review": "no-mistakes",
    "browser": "agent-browser",
    "specs": "local",
    "notify": "on",
    "ui_refs": "none",
}

CHOICES = {
    "tracker": ("github", "linear", "none"),
    "review": ("no-mistakes", "greptile", "none"),
    "browser": ("agent-browser", "chrome-devtools-axi", "playwright-axi"),
    "specs": ("local", "committed"),
    "notify": ("on", "off"),
    "ui_refs": ("mobbin", "none"),
}
KNOWN = set(DEFAULTS) | {"linear_team", "branch_max", "commands", "deploy_steps", "verifiers"}
PLACEHOLDERS = {"type", "slug", "id", "user"}


class Invalid(Exception):
    def __init__(self, problems):
        super().__init__("\n".join(problems))
        self.problems = problems


def main_checkout(start):
    try:
        common = subprocess.run(
            ["git", "-C", start, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return start
    return common[:-5] if common.endswith("/.git") else start


def scalar(v, n=0):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if v[:1] in "\"'":
        raise Invalid([f"line {n}: the quote is not closed: {v}"])
    if v.startswith("[") and v.endswith("]"):
        return [scalar(x, n) for x in v[1:-1].split(",") if x.strip()]
    if v.startswith("[") or v.endswith("]"):
        raise Invalid([f"line {n}: the list is not closed: {v}"])
    if v in ("true", "false"):
        return v == "true"
    if v in ("", "null", "~"):
        return None
    try:
        return int(v)
    except ValueError:
        return v


def strip_comment(line):
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()


def parse(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise Invalid(["line 1: the file must start with a YAML header between two --- lines"])
    data, open_key, problems, closed = {}, None, [], False
    for n, raw in enumerate(lines[1:], start=2):
        if raw.strip() == "---":
            closed = True
            break
        try:
            line = strip_comment(raw)
            if not line.strip():
                continue
            if "\t" in line[:len(line) - len(line.lstrip())]:
                raise Invalid([f"line {n}: indent with spaces, not tabs"])
            indented = line[0] == " "
            body = line.strip()
            if indented:
                if not open_key:
                    raise Invalid([f"line {n}: an indented line must be under a key that has no value: {body}"])
                if body == "-" or body.startswith("- "):
                    if data[open_key] is None:
                        data[open_key] = []
                    if not isinstance(data[open_key], list):
                        raise Invalid([f"line {n}: {open_key} mixes list items and keys"])
                    data[open_key].append(scalar(body[1:], n))
                elif ":" in body:
                    if data[open_key] is None:
                        data[open_key] = {}
                    if not isinstance(data[open_key], dict):
                        raise Invalid([f"line {n}: {open_key} mixes list items and keys"])
                    k, v = body.split(":", 1)
                    data[open_key][k.strip()] = scalar(v, n)
                else:
                    raise Invalid([f"line {n}: expected '- item' or 'key: value' under {open_key}: {body}"])
                continue
            if ":" not in body:
                raise Invalid([f"line {n}: expected 'key: value': {body}"])
            k, v = body.split(":", 1)
            k = k.strip()
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", k):
                raise Invalid([f"line {n}: not a valid key: {k}"])
            if k in data:
                raise Invalid([f"line {n}: {k} is set twice"])
            if v.strip():
                data[k] = scalar(v, n)
                open_key = None
            else:
                data[k] = None
                open_key = k
        except Invalid as e:
            problems += e.problems
    if not closed:
        problems.append("the YAML header has no closing --- line")
    if problems:
        raise Invalid(problems)
    return {k: v for k, v in data.items() if v is not None}


def validate(data):
    problems = []
    for key, allowed in CHOICES.items():
        v = data.get(key)
        if v is True and key == "notify":
            v = data[key] = "on"
        elif v is False and key == "notify":
            v = data[key] = "off"
        if v is not None and v not in allowed:
            problems.append(f"{key}: '{v}' is not one of {', '.join(allowed)}")
    base = data.get("base")
    if not isinstance(base, str) or not base or re.search(r"\s|\.\.|^-|[~^:?*\\[]", base):
        problems.append(f"base: '{base}' is not a branch name")
    if data.get("tracker") == "linear" and not data.get("linear_team"):
        problems.append("linear_team: tracker is linear, so set the Linear team key (for example ENG)")
    branch = data.get("branch")
    if isinstance(branch, str):
        used = set(re.findall(r"{([^}]*)}", branch))
        if used - PLACEHOLDERS:
            problems.append(f"branch: unknown placeholder {{{sorted(used - PLACEHOLDERS)[0]}}} (use {{type}} {{slug}} {{id}} {{user}})")
        if not used & {"slug", "id"}:
            problems.append("branch: needs {slug} or {id}, so each build gets its own branch")
    else:
        problems.append(f"branch: '{branch}' is not a text")
    commit = data.get("commit")
    if commit != "conventional" and (not isinstance(commit, str) or "{summary}" not in commit):
        problems.append(f"commit: '{commit}' needs {{summary}}, or use conventional")
    bm = data.get("branch_max")
    if bm is not None and (not isinstance(bm, int) or isinstance(bm, bool) or bm < 10):
        problems.append(f"branch_max: '{bm}' is not a number of 10 or more")
    cmds = data.get("commands")
    if cmds is not None and not isinstance(cmds, dict):
        problems.append("commands: must be keys under it, for example '  test: pnpm test'")
    for key in ("deploy_steps", "verifiers"):
        v = data.get(key)
        if v is not None and not isinstance(v, list):
            problems.append(f"{key}: must be a list, for example [a, b] or lines that start with '- '")
    for key in data:
        if key not in KNOWN:
            problems.append(f"{key}: not a cook.md field (see docs/cook-md.md)")
    return problems


def load(path):
    with open(path, encoding="utf-8") as f:
        data = {**DEFAULTS, **parse(f.read())}
    problems = validate(data)
    if problems:
        raise Invalid(problems)
    return data


def lookup(data, key):
    cur = data
    for part in key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def main(argv):
    repo = os.getcwd()
    if len(argv) >= 2 and argv[0] == "--repo":
        repo, argv = argv[1], argv[2:]
    if not argv or argv[0] not in ("get", "json", "path", "check"):
        print("usage: config.py [--repo <dir>] get <key> [default] | json | path | check", file=sys.stderr)
        return 1
    path = os.environ.get("COOK_CONFIG") or os.path.join(main_checkout(repo), ".agents", "cook.md")
    if argv[0] == "path":
        print(path)
        return 0 if os.path.exists(path) else 2
    if not os.path.exists(path):
        if argv[0] == "get" and len(argv) >= 2 and (len(argv) >= 3 or argv[1] in DEFAULTS):
            print(argv[2] if len(argv) >= 3 else DEFAULTS[argv[1]])
            return 0
        print(f"no cook.md at {path}: run /cook-init", file=sys.stderr)
        return 2
    try:
        data = load(path)
    except Invalid as e:
        print(f"{path} is not valid:", file=sys.stderr)
        for p in e.problems:
            print(f"  {p}", file=sys.stderr)
        return 4
    if argv[0] == "check":
        print(f"{path}: ok")
        return 0
    if argv[0] == "json":
        print(json.dumps(data, indent=1))
        return 0
    if len(argv) < 2:
        return 1
    value = lookup(data, argv[1])
    if value is None:
        if len(argv) >= 3:
            print(argv[2])
            return 0
        return 3
    if isinstance(value, dict):
        print(json.dumps(value, indent=1))
    else:
        print("\n".join(map(str, value)) if isinstance(value, list) else value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
