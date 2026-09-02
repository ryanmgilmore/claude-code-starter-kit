#!/usr/bin/env bash
#
# install.sh — link this repo into ~/.claude on a machine.
#
# Run once after cloning claude-config to a new machine (e.g. the M1):
#
#   git clone <url> ~/dev/claude-config
#   ~/dev/claude-config/bin/install.sh
#
# Also safe to re-run on an existing machine — it repairs symlinks that were
# replaced by real files (see "settings.json caveat" in README.md).
#
# What it links:
#   ~/.claude/CLAUDE.md      -> repo CLAUDE.md      (loaded every session)
#   ~/.claude/settings.json  -> repo settings.json  (hooks, model, plugins)
#   ~/.claude/skills         -> repo skills/        (on-demand skills)
#   ~/.claude/projects/<key>/memory -> repo memory/<name>/
#
# Memory keys are derived from the project's ABSOLUTE PATH. Projects at the same
# path on every machine is the recommended setup, and the default. If a machine
# cannot manage that, set its workspace root in path-map.tsv — bin/lib-paths.sh
# then names memory canonically, by path relative to that root, so both machines
# still agree.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE="$HOME/.claude"

CLAUDE_CONFIG_REPO="$REPO"
# shellcheck source=lib-paths.sh
. "$REPO/bin/lib-paths.sh"

link() { # link <target> <linkname>
  local target="$1" name="$2"
  if [ -L "$name" ]; then
    [ "$(readlink "$name")" = "$target" ] && { echo "  ok       ${name/#$HOME/~}"; return; }
    rm "$name"
  elif [ -e "$name" ]; then
    local bak="$name.pre-claude-config.$(date +%Y%m%d%H%M%S)"
    mv "$name" "$bak"
    echo "  backed up ${bak/#$HOME/~}"
  fi
  mkdir -p "$(dirname "$name")"
  ln -s "$target" "$name"
  echo "  linked   ${name/#$HOME/~}"
}

echo "claude-config: $REPO"
mkdir -p "$CLAUDE/projects"

link "$REPO/CLAUDE.md"     "$CLAUDE/CLAUDE.md"
link "$REPO/settings.json" "$CLAUDE/settings.json"
# Task lists: small, structured, and readable on either machine. Created if absent
# so a fresh machine starts syncing them from its first session rather than
# dangling a symlink. Prompt history is deliberately NOT synced — see README.
mkdir -p "$REPO/tasks" "$REPO/skills"
link "$REPO/skills" "$CLAUDE/skills"
link "$REPO/tasks"  "$CLAUDE/tasks"

echo "memory:"
shopt -s nullglob
for dir in "$REPO"/memory/*/; do
  name="$(basename "$dir")"
  # Key derivation, including the reserved `_workspace` name and this machine's
  # workspace root, lives in bin/lib-paths.sh.
  link "$REPO/memory/$name" "$CLAUDE/projects/$(key_for_name "$name")/memory"
done

# Pick up memory this machine created for projects not yet in the repo.
echo "adopting any unlinked memory:"
"$REPO/bin/adopt-memory.sh" | sed 's/^/  /' || true

echo
echo "done. Verify with:  ls -la ~/.claude"
echo "Projects must be cloned to ~/dev/<name> for these memory keys to match."
