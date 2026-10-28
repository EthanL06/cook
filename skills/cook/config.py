#!/usr/bin/env python3
"""Read the YAML header of a project's .agents/cook.md.

Usage: config.py [--repo <dir>] get <key> [default]
       config.py [--repo <dir>] json
       config.py [--repo <dir>] path

<key> can be nested with dots, for example commands.dev.
The header supports the small YAML subset that cook.md uses: scalars,
quoted strings, inline lists ([a, b]), block lists (- a) and one level
of nested maps. A full YAML parser is not a dependency on purpose.

The file is read from the main checkout, so a build in a worktree reads
the same config as the repo it came from.

Exit codes: 0 found, 1 bad arguments, 2 no cook.md, 3 key not set and no default.
"""
import json
import os
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
}


def main_checkout(start):
    try:
        common = subprocess.run(
            ["git", "-C", start, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return start
    return common[:-5] if common.endswith("/.git") else start


def scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if v.startswith("[") and v.endswith("]"):
        return [scalar(x) for x in v[1:-1].split(",") if x.strip()]
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
        return {}
    data, open_key = {}, None
    for raw in lines[1:]:
        if raw.strip() == "---":
            break
        line = strip_comment(raw)
        if not line.strip():
            continue
        indented = line[0] in " \t"
        body = line.strip()
        if indented and open_key:
            if body.startswith("- "):
                if not isinstance(data[open_key], list):
                    data[open_key] = []
                data[open_key].append(scalar(body[2:]))
            elif ":" in body:
                if not isinstance(data[open_key], dict):
                    data[open_key] = {}
                k, v = body.split(":", 1)
                data[open_key][k.strip()] = scalar(v)
            continue
        if ":" not in body:
            continue
        k, v = body.split(":", 1)
        k = k.strip()
        if v.strip():
            data[k] = scalar(v)
            open_key = None
        else:
            data[k] = None
            open_key = k
    return {k: v for k, v in data.items() if v is not None}


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
    if not argv or argv[0] not in ("get", "json", "path"):
        print("usage: config.py [--repo <dir>] get <key> [default] | json | path", file=sys.stderr)
        return 1
    path = os.path.join(main_checkout(repo), ".agents", "cook.md")
    if argv[0] == "path":
        print(path)
        return 0 if os.path.exists(path) else 2
    if not os.path.exists(path):
        if argv[0] == "get" and len(argv) >= 2 and (len(argv) >= 3 or argv[1] in DEFAULTS):
            print(argv[2] if len(argv) >= 3 else DEFAULTS[argv[1]])
            return 0
        print(f"no cook.md at {path}: run /cook-init", file=sys.stderr)
        return 2
    with open(path, encoding="utf-8") as f:
        data = {**DEFAULTS, **parse(f.read())}
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
    print("\n".join(map(str, value)) if isinstance(value, list) else value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
