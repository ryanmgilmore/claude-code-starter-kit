#!/usr/bin/env bash
#
# adopt-memory.sh — pull newly-created project memory into claude-config.
#
# Claude Code writes memory to ~/.claude/projects/<path-key>/memory/. For
# projects linked by install.sh that is a symlink into this repo, so the content
# is versioned and synced. For a project that did not exist when install.sh last
# ran, Claude Code creates a REAL directory instead — and that memory silently
# lives on one machine only.
#
# This closes that gap: any real memory directory is moved into the repo and
# replaced with a symlink. Run it manually, or let `sync.sh push` call it at
# session end (when memory writes have finished).
#
#   adopt-memory.sh              adopt anything new
#   adopt-memory.sh --dry-run    report without touching anything
#
# Only keys under ~/dev are adopted. Legacy keys from before the ~/Documents
# move are left alone deliberately — they refer to paths that no longer exist.
#
# ~/dev itself is a session directory too — the workspace repo. Its key has no
# project suffix, so it is mapped to the reserved name `_workspace`. The leading
# underscore cannot collide with a real project, since those are named after a
# directory under ~/dev.
#
# Never fails: it runs from a session hook, and a broken hook costs more than
# memory being adopted one session later.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS="$HOME/.claude/projects"
DRY=0

# How a path becomes a key — and which root this machine uses — lives in one
# place, so a machine whose workspace is not at ~/dev still finds its memory.
CLAUDE_CONFIG_REPO="$REPO"
# shellcheck source=lib-paths.sh
. "$REPO/bin/lib-paths.sh" 2>/dev/null || { echo "  lib-paths.sh missing" >&2; exit 0; }
[ "${1:-}" = "--dry-run" ] && DRY=1

[ -d "$PROJECTS" ] || exit 0
mkdir -p "$REPO/memory" 2>/dev/null || exit 0

adopted=0

for dir in "$PROJECTS"/*/; do
  key="$(basename "$dir")"
  mem="$dir/memory"

  # Already a symlink, or no memory written yet — nothing to do.
  [ -L "$mem" ] && continue
  [ -d "$mem" ] || continue

  # Empty directories carry nothing; skip rather than create clutter.
  [ -n "$(ls -A "$mem" 2>/dev/null)" ] || continue

  # Only keys under this machine's workspace root, plus the root itself.
  if ! name="$(name_for_key "$key")"; then
    echo "  skip (not under $(workspace_root)): $key" >&2
    continue
  fi

  target="$REPO/memory/$name"

  if [ -e "$target" ]; then
    # Both sides have content for the same project — almost certainly the other
    # machine adopted it first. Merging silently could lose an edit, so stop and
    # let a human look.
    echo "  CONFLICT: $name exists in claude-config and as a real dir at $mem" >&2
    echo "            Merge by hand, then re-run." >&2
    continue
  fi

  if [ "$DRY" = "1" ]; then
    echo "  would adopt: $key -> memory/$name ($(ls -A "$mem" | wc -l | tr -d ' ') files)"
    adopted=$((adopted+1))
    continue
  fi

  if mv "$mem" "$target" 2>/dev/null && ln -s "$target" "$mem" 2>/dev/null; then
    echo "  adopted: $key -> memory/$name ($(ls -A "$target" | wc -l | tr -d ' ') files)"
    adopted=$((adopted+1))
  else
    # Put it back if the symlink could not be created, rather than leaving the
    # memory orphaned inside the repo with nothing pointing at it.
    [ -d "$target" ] && [ ! -e "$mem" ] && mv "$target" "$mem" 2>/dev/null
    echo "  FAILED to adopt $key" >&2
  fi
done

[ "$adopted" -gt 0 ] && echo "claude-config: adopted $adopted project memory dir(s)"
exit 0
