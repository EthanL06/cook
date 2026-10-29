#!/usr/bin/env python3
"""List the machines that can run a cook build.

Usage: machines.py [--origin <git remote url or owner/name>] [--json]

Without Tailscale, the only machine is this one. With Tailscale, each online
macOS or Linux peer is checked over SSH (BatchMode, 5 s timeout) for git, gh,
paseo, node (for Lavish), an agent CLI (claude or codex), and the cook skill.
With --origin, it also finds the checkout of that repo on each machine
(a git repo under ~/Developer, ~/code, ~/src, ~/projects, ~/repos or ~ whose
origin matches). A machine is "ready" when nothing is missing.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

TAILSCALE = [shutil.which("tailscale") or "", os.environ.get("COOK_TAILSCALE_APP", "/Applications/Tailscale.app/Contents/MacOS/Tailscale")]
PROBE = r'''
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
want="$1"
printf 'host=%s\nhome=%s\n' "$(hostname)" "$HOME"
for t in git gh paseo node claude codex; do printf '%s=%s\n' "$t" "$(command -v $t)"; done
for d in "$HOME/.agents/skills/cook" "$HOME/.claude/skills/cook"; do [ -f "$d/SKILL.md" ] && { echo skill=1; break; }; done
if [ -n "$want" ]; then
  for root in "$HOME/Developer" "$HOME/code" "$HOME/src" "$HOME/projects" "$HOME/repos" "$HOME"; do
    [ -d "$root" ] || continue
    for g in "$root"/*/.git "$root"/*/*/.git; do
      [ -d "$g" ] || continue
      d=${g%/.git}
      u=$(git -C "$d" config --get remote.origin.url) || continue
      s=$(printf '%s' "$u" | sed -E 's#^.*(github\.com|gitlab\.com|bitbucket\.org)[:/]##; s#\.git$##')
      [ "$s" = "$want" ] && { echo "repo=$d"; exit 0; }
    done
  done
fi
:
'''


def slug(origin):
    return re.sub(r"\.git$", "", re.sub(r"^.*(github\.com|gitlab\.com|bitbucket\.org)[:/]", "", origin or ""))


def tailscale_status():
    for exe in TAILSCALE:
        if exe and os.path.exists(exe):
            p = subprocess.run([exe, "status", "--json"], capture_output=True, text=True)
            if p.returncode == 0:
                return json.loads(p.stdout)
    return None


def probe(name, local, want):
    cmd = ["sh", "-c", PROBE, "probe", want] if local else \
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", name, "sh", "-s", "--", want]
    try:
        p = subprocess.run(cmd, input=None if local else PROBE, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return {"ssh": False, "error": "timeout"}
    if p.returncode:
        return {"ssh": False, "error": (p.stderr.strip().splitlines() or ["ssh failed"])[-1][:120]}
    kv = dict(line.split("=", 1) for line in p.stdout.splitlines() if "=" in line)
    return {"ssh": True, **{k: v for k, v in kv.items() if v}}


def ts_name(node):
    return (node.get("DNSName") or "").split(".")[0] or node["HostName"].lower()


def main(argv):
    want = slug(argv[argv.index("--origin") + 1]) if "--origin" in argv and argv.index("--origin") + 1 < len(argv) else ""
    st = tailscale_status()
    if st:
        me = st["Self"]
        rows = [{"name": ts_name(me), "dns": me.get("DNSName", "").rstrip("."), "ip": (me.get("TailscaleIPs") or [""])[0],
                 "os": me.get("OS"), "online": True, "self": True}]
        for peer in (st.get("Peer") or {}).values():
            if peer.get("OS") not in ("macOS", "linux"):
                continue
            rows.append({"name": ts_name(peer), "dns": peer.get("DNSName", "").rstrip("."),
                         "ip": (peer.get("TailscaleIPs") or [""])[0], "os": peer.get("OS"),
                         "online": bool(peer.get("Online")), "self": False})
    else:
        rows = [{"name": "local", "dns": "", "ip": "", "os": sys.platform, "online": True, "self": True}]
    targets = [r for r in rows if r["online"]]
    with ThreadPoolExecutor(max_workers=8) as ex:
        for r, res in zip(targets, ex.map(lambda r: probe(r["name"], r["self"], want), targets)):
            r.update(res)
    for r in rows:
        missing = [k for k in ("git", "gh", "paseo", "node") if not r.get(k)]
        if not (r.get("claude") or r.get("codex")):
            missing.append("claude or codex")
        if not r.get("skill"):
            missing.append("cook skill")
        if want and not r.get("repo"):
            missing.append(f"checkout of {want}")
        r["missing"] = missing if r.get("ssh") else ["ssh"] if r["online"] else ["offline"]
        r["ready"] = r["online"] and r.get("ssh", False) and not missing
        r["paseoHost"] = None if r["self"] else f"ssh://{r['name']}"
    if "--json" in argv:
        print(json.dumps(rows, indent=1))
        return 0
    for r in rows:
        tag = "this machine" if r["self"] else r["os"]
        state = "ready" if r["ready"] else "missing: " + ", ".join(r["missing"])
        print(f"{r['name']:<20} {tag:<13} {state}" + (f"   repo={r['repo']}" if r.get("repo") else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
