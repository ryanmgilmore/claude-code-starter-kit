#!/usr/bin/env bash
#
# digest.sh — leave a small, durable record of what a session did.
#
# Run from the SessionEnd hook, which supplies JSON on stdin containing
# `transcript_path`, `session_id` and `cwd`. Also callable by hand for testing:
#
#   digest.sh <transcript_path> <session_id> <cwd>
#
# WHY THIS EXISTS
#
# Transcripts do not sync between machines, and they should not: Claude Code keeps
# a rolling 30-day window of them, while git would accumulate them permanently.
# Memory carries conclusions, but nothing recorded *that a session happened* — so
# from the other machine there was no way to know what yesterday was spent on.
#
# A digest is one small Markdown file per session: what was asked, what was
# touched, when, and on which machine. A year of them is a few megabytes, they
# diff cleanly, they are greppable, and they are readable in five years.
#
# DESIGN CHOICES WORTH KNOWING
#
# 1. No model call. The obvious implementation asks Claude to summarise the
#    session — but a hook that runs `claude` risks spawning a session that fires
#    hooks of its own, costs tokens on every exit, and adds seconds to it. This
#    extracts what is already in the transcript instead. The result is mechanical
#    rather than insightful, and it is honest about that.
# 2. The transcript format is internal to Claude Code and changes between
#    versions, so parsing is defensive: unknown shapes are skipped, and a partial
#    digest is written rather than none.
# 3. Trivial sessions are skipped. Two prompts of "ls" is clutter, and clutter is
#    what makes people stop reading a log.
# 4. Never fails. Exits 0 on missing input, unreadable transcripts, or garbage.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_CONFIG_REPO="$REPO"
# shellcheck source=lib-paths.sh
. "$REPO/bin/lib-paths.sh" 2>/dev/null || exit 0

MIN_TURNS="${DIGEST_MIN_TURNS:-3}"     # below this, not worth a file

TRANSCRIPT="${1:-}"; SESSION="${2:-}"; CWD="${3:-}"

# The hook delivers JSON on stdin. Read it only when it is there, and never block
# waiting for input that will not come.
if [ -z "$TRANSCRIPT" ] && [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
  if [ -n "$payload" ]; then
    read -r TRANSCRIPT SESSION CWD <<EOF
$(printf '%s' "$payload" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("transcript_path","-") or "-", d.get("session_id","-") or "-", d.get("cwd","-") or "-")
' 2>/dev/null || echo "- - -")
EOF
  fi
fi

[ -n "$TRANSCRIPT" ] && [ "$TRANSCRIPT" != "-" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0
[ -n "$CWD" ] && [ "$CWD" != "-" ] || CWD="$PWD"

# Which project this belongs to, named the same way memory is.
root="$(workspace_root)"
case "$CWD" in
  "$root")   project="$WORKSPACE_MEM" ;;
  "$root"/*) project="$(printf '%s' "${CWD#"$root"/}" | tr '/' '-')" ;;
  *)         project="$(basename "$CWD")" ;;
esac

machine="$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || echo unknown)"
branch="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
short="$(printf '%s' "${SESSION:-unknown}" | cut -c1-8)"

out_dir="$REPO/digests/$project"
mkdir -p "$out_dir" 2>/dev/null || exit 0

TRANSCRIPT="$TRANSCRIPT" SESSION="${SESSION:-unknown}" SHORT="$short" \
PROJECT="$project" MACHINE="$machine" BRANCH="$branch" \
OUT_DIR="$out_dir" MIN_TURNS="$MIN_TURNS" python3 <<'PY' 2>/dev/null || exit 0
import json, os, sys, datetime, re

tp   = os.environ["TRANSCRIPT"]
outd = os.environ["OUT_DIR"]
minT = int(os.environ.get("MIN_TURNS", "3"))

prompts, files, times = [], {}, []

def text_of(content):
    """Message content is a string in some versions and a list of blocks in
    others. Accept either; ignore anything else."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str):
                out.append(b["text"])
        return "\n".join(out)
    return ""

with open(tp, "r", errors="replace") as fh:
    for line in fh:
        try:
            d = json.loads(line)
        except Exception:
            continue                      # a partial or reshaped line is not fatal
        if not isinstance(d, dict):
            continue

        ts = d.get("timestamp")
        if isinstance(ts, str):
            times.append(ts)

        msg = d.get("message")
        if isinstance(msg, dict):
            role = msg.get("role")
            if role == "user":
                t = text_of(msg.get("content")).strip()
                # Tool results and injected context are not things the human asked.
                if t and not t.startswith("<") and "tool_result" not in t[:40]:
                    prompts.append(" ".join(t.split()))
            for b in (msg.get("content") if isinstance(msg.get("content"), list) else []):
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                    for key in ("file_path", "path", "notebook_path"):
                        p = inp.get(key)
                        if isinstance(p, str) and p:
                            files[p] = files.get(p, 0) + 1

if len(prompts) < minT:
    sys.exit(1)                            # too small to be worth a file

def day(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone()
    except Exception:
        return None

start, end = (day(times[0]) if times else None), (day(times[-1]) if times else None)
date_s = start.strftime("%Y-%m-%d %H:%M") if start else "unknown"
day_s  = start.strftime("%Y-%m-%d") if start else "0000-00-00"
mins   = int((end - start).total_seconds() // 60) if (start and end) else 0

def clip(s, n=200):
    return s if len(s) <= n else s[: n - 1] + "…"

lines = []
lines.append("---")
lines.append(f"session: {os.environ['SESSION']}")
lines.append(f"project: {os.environ['PROJECT']}")
lines.append(f"machine: {os.environ['MACHINE']}")
lines.append(f"branch: {os.environ['BRANCH']}")
lines.append(f"date: {date_s}")
lines.append(f"prompts: {len(prompts)}")
lines.append(f"minutes: {mins}")
lines.append("---")
lines.append("")
lines.append(f"# {clip(prompts[0], 110)}")
lines.append("")
lines.append("Mechanical digest — extracted from the transcript, not written by Claude.")
lines.append("The conversation itself stays on the machine that had it.")
lines.append("")
lines.append("## Asked")
lines.append("")
for p in prompts[:10]:
    lines.append(f"- {clip(p)}")
if len(prompts) > 10:
    lines.append(f"- …and {len(prompts) - 10} more")
if files:
    lines.append("")
    lines.append("## Files touched")
    lines.append("")
    home = os.path.expanduser("~")
    for p, n in sorted(files.items(), key=lambda kv: -kv[1])[:15]:
        shown = p.replace(home, "~")
        lines.append(f"- `{shown}`" + (f" ({n}×)" if n > 1 else ""))
    if len(files) > 15:
        lines.append(f"- …and {len(files) - 15} more")
lines.append("")

path = os.path.join(outd, f"{day_s}-{os.environ['SHORT']}.md")
with open(path, "w") as fh:
    fh.write("\n".join(lines))
print(path)
PY

exit 0
