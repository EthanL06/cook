#!/usr/bin/env python3
"""Render cook-status from the records that status.sh gathers on stdin.

Usage: status.sh gathers; python3 -I status.py [ref] < records
Records: BUILD<TAB>machine<TAB>agent-id<TAB>step<TAB>ref<TAB>cwd, then EV<TAB><event line> for that build,
RUN<TAB>machine<TAB><run state JSON>, then EV lines for the run's agent, DOWN<TAB>machine for a machine that does not
answer, and HIST<TAB><event line> for every event log on this machine (for typical step times).
A run whose agents are all gone from Paseo is a build too: it waits on you, for /cook resume.
"""
import json, sys, datetime as dt
want = sys.argv[1] if len(sys.argv) > 1 else ""
now = dt.datetime.now(dt.timezone.utc)
YOU = {"plan", "blocked", "ready"}

def parse(line):
    head, _, rest = line.partition(" | ")
    text, _, url = rest.rpartition(" | ")
    p = head.split()
    if len(p) < 5 or p[:2] != ["COOK", "EVENT"]:
        return None
    try:
        t = dt.datetime.fromisoformat(p[2].replace("Z", "+00:00"))
    except ValueError:
        return None
    return {"t": t, "step": p[3], "ref": p[4], "text": text.strip(), "url": "" if url.strip() == "-" else url.strip()}

def age(td):
    s = int(td.total_seconds())
    if s < 3600: return f"{max(s // 60, 0)}m"
    if s < 86400: return f"{s // 3600}h{(s % 3600) // 60:02d}m" if s < 36000 else f"{s // 3600}h"
    return f"{s // 86400}d"

builds, runs, hist, down, last = [], [], [], [], None
for line in sys.stdin.read().splitlines():
    kind, _, rest = line.partition("\t")
    if kind == "BUILD":
        m, i, step, r, cwd = rest.split("\t")
        last = {"m": m, "id": i, "step": step, "ref": r, "cwd": cwd, "ev": [], "run": None}
        builds.append(last)
    elif kind == "RUN":
        m, _, raw = rest.partition("\t")
        try:
            last = {"m": m, "state": json.loads(raw), "ev": []}
        except ValueError:
            last = None
            continue
        runs.append(last)
    elif kind == "DOWN":
        down.append(rest)
    elif kind == "EV" and last is not None:
        e = parse(rest)
        if e: last["ev"].append(e)
    elif kind == "HIST":
        e = parse(rest)
        if e: hist.append(e)

for r in runs:
    st = r["state"]
    live = [b for b in builds if b["m"] == r["m"] and b["id"] in st.get("agents", [])]
    for b in live:
        b["run"] = st
    if not live and st.get("step") != "ready":
        builds.append({"m": r["m"], "id": st.get("agent_id", ""), "step": st.get("step", "?"), "ref": st.get("ref", "?"),
                       "cwd": st.get("cwd", ""), "ev": r["ev"], "run": st, "gone": True})

# Typical time per step: from the first event of a step to the next event of another step, per build ref.
typical = {}
by_ref = {}
for e in hist: by_ref.setdefault(e["ref"], []).append(e)
for evs in by_ref.values():
    evs.sort(key=lambda e: e["t"])
    for a, b in zip(evs, evs[1:]):
        if a["step"] != b["step"]:
            typical.setdefault(a["step"], []).append((b["t"] - a["t"]).total_seconds())

for b in builds:
    ev = b["ev"]
    since = ev[-1]["t"] if ev else now
    for e in reversed(ev):
        if e["step"] != b["step"]: break
        since = e["t"]
    b["since"], b["last"] = since, (ev[-1] if ev else None)
    b["who"] = "you" if b["step"] in YOU else "agent"
    if b.get("gone"):
        b["who"] = "you"
        if not ev and b["run"].get("updated"):
            b["since"] = dt.datetime.fromisoformat(b["run"]["updated"].replace("Z", "+00:00"))

if want:
    w = want.lstrip("#")
    sel = [b for b in builds if b["ref"].lstrip("#") == w or b["id"].startswith(want)]
    if not sel:
        print(f"No cook build matches {want}.")
        sys.exit(2)
    b = sel[0]
    print(f"{b['ref']} · {b['m']} · agent {b['id'][:7]} · {b['cwd']}")
    print(f"step     {b['step']} for {age(now - b['since'])} · waiting on {b['who']}")
    if b.get("gone"):
        print(f"agent    gone from Paseo. Continue the build with /cook resume {b['ref']}")
    st = b.get("run")
    if st:
        base = f" from {st['base']}" if st.get("base") else ""
        print(f"branch   {st.get('branch', '?')}{base} · head {str(st.get('head', ''))[:7] or '?'}")
        sp = st.get("spec") or {}
        print(f"spec     approved {sp['approved']} · copy {sp['copy']}" if sp.get("approved") else "spec     not approved yet")
        v = st.get("verify") or {}
        if v:
            print(f"verify   {v['verdict']} on {v['head'][:7]} (attempt {v['attempts']}) · {v['copy']}")
    links = [e["url"] for e in b["ev"] if e["url"]]
    spec = next((u for u in reversed(links) if "/pull/" not in u), "")
    pr = next((u for u in reversed(links) if "/pull/" in u), "")
    print(f"links    spec {spec or '(none yet)'}   PR {pr or '(none yet)'}")
    print("recent")
    for e in b["ev"][-10:][::-1]:
        print(f"  {e['t'].astimezone().strftime('%m-%d %H:%M')}  {e['step']:<8} {e['text']}" + (f"  {e['url']}" if e["url"] else ""))
    t = typical.get(b["step"])
    if t and len(t) >= 3:
        lo, hi = sorted(t)[len(t) // 4], sorted(t)[(3 * len(t)) // 4]
        print(f"eta      no guess. {b['step']} usually takes {age(dt.timedelta(seconds=lo))}-{age(dt.timedelta(seconds=hi))} here ({len(t)} past builds).")
    else:
        print("eta      no guess, and not enough past builds to say how long this step usually takes.")
    sys.exit(0)

def down_note():
    if down:
        print(f"Not reachable: {', '.join(down)}. Builds on {'it' if len(down) == 1 else 'them'} are not shown.")

if not builds:
    print("No cook builds are running. Start one with /cook.")
    down_note()
    sys.exit(0)
builds.sort(key=lambda b: (b["who"] != "you", b["since"]))
rows = [("REF", "STEP", "WAITING ON", "FOR", "MACHINE", "LAST")]
for b in builds:
    last = b["last"]
    text = (last["text"] if last else "no events yet")
    if len(text) > 70: text = text[:67] + "..."
    if last and last["url"]: text += f"  {last['url']}"
    if b.get("gone"):
        text = f"agent is gone. Run /cook resume {b['ref']}"
    rows.append((b["ref"], b["step"], "you (resume)" if b.get("gone") else b["who"], age(now - b["since"]), b["m"], text))
wid = [max(len(r[i]) for r in rows) for i in range(5)]
for r in rows:
    print("  ".join(r[i].ljust(wid[i]) for i in range(5)) + "  " + r[5])
yours = [b for b in builds if b["who"] == "you"]
if yours:
    o = yours[0]
    print(f"\n{len(yours)} {'builds wait' if len(yours) != 1 else 'build waits'} on you. Oldest: {o['ref']} ({age(now - o['since'])}).")
else:
    print("\nNothing waits on you.")
down_note()
