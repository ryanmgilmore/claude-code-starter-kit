#!/usr/bin/env bash
#
# lib-paths.sh — the one place that knows how a project path becomes a memory key.
#
# Sourced by install.sh, adopt-memory.sh and sync.sh. Not executable on its own.
#
# WHY THIS EXISTS
#
# Claude Code derives each project's storage key from its ABSOLUTE PATH, with
# every non-alphanumeric character replaced by "-":
#
#   ~/dev/robotics/armctl  ->  -Users-you-dev-robotics-armctl
#
# Until now the scripts hardcoded "-Users-$(id -un)-dev-", which made identical
# absolute paths on both machines a load-bearing, unforgiving invariant: a machine
# that could not host ~/dev at the same path would silently find no memory at all.
#
# Here the workspace root is CONFIGURABLE, and memory directories are named
# canonically — by their path RELATIVE to that root. So `robotics/armctl` is
# `memory/robotics-armctl` on every machine, whatever the root happens to be
# locally, and the two machines agree without needing identical paths.
#
# Identical paths remain the recommended setup and the default. This only removes
# the cliff.
#
# RESOLUTION ORDER for the workspace root:
#   1. $CLAUDE_WORKSPACE_ROOT              (env override, wins outright)
#   2. path-map.tsv row for this computer  (by name, from scutil/hostname)
#   3. path-map.tsv row for "*"            (shared default)
#   4. $HOME/dev                           (the default everywhere)

# The reserved canonical name for the workspace root itself — a session started in
# ~/dev rather than in a project under it. Its key has no project suffix, and the
# leading underscore cannot collide with a real project, since those are named
# after a directory under the root.
WORKSPACE_MEM="_workspace"

_this_machine() { scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || echo unknown; }

# workspace_root — this machine's ~/dev equivalent, without a trailing slash.
workspace_root() {
  if [ -n "${CLAUDE_WORKSPACE_ROOT:-}" ]; then
    printf '%s\n' "${CLAUDE_WORKSPACE_ROOT%/}"
    return 0
  fi

  local map="${CLAUDE_CONFIG_REPO:-$HOME/dev/claude-config}/path-map.tsv"
  if [ -f "$map" ]; then
    local me row_machine row_root fallback=""
    me="$(_this_machine)"
    while IFS=$'\t' read -r row_machine row_root; do
      case "$row_machine" in ''|\#*) continue ;; esac
      [ -n "$row_root" ] || continue
      # Expand $HOME and a leading ~ so the file stays portable.
      row_root="${row_root/#\~/$HOME}"
      row_root="${row_root//\$HOME/$HOME}"
      # A root that does not exist on this machine cannot be this machine's root.
      # This file SYNCS, so a "*" row naming one machine's custom location would
      # otherwise become every machine's — and a machine would look for its memory
      # inside a path belonging to a different computer. Custom roots belong on a
      # machine-name row; this check is what stops the mistake being silent.
      [ -d "$row_root" ] || continue
      if [ "$row_machine" = "$me" ]; then printf '%s\n' "${row_root%/}"; return 0; fi
      [ "$row_machine" = "*" ] && fallback="${row_root%/}"
    done < "$map"
    [ -n "$fallback" ] && { printf '%s\n' "$fallback"; return 0; }
  fi

  printf '%s\n' "$HOME/dev"
}

# key_prefix — how Claude Code spells this machine's workspace root as a key
# component: every non-alphanumeric character becomes "-".
key_prefix() {
  printf '%s\n' "$(workspace_root)" | sed 's/[^A-Za-z0-9]/-/g'
}

# key_for_name <canonical-name> — the local session key for a memory directory.
key_for_name() {
  local name="$1" prefix
  prefix="$(key_prefix)"
  if [ "$name" = "$WORKSPACE_MEM" ]; then printf '%s\n' "$prefix"; else printf '%s\n' "$prefix-$name"; fi
}

# name_for_key <session-key> — the canonical memory name for a session key, or
# nothing at all if that key is not under this machine's workspace root. Keys from
# elsewhere (a project outside the workspace, or a legacy path that no longer
# exists) are deliberately not adopted.
name_for_key() {
  local key="$1" prefix
  prefix="$(key_prefix)"
  case "$key" in
    "$prefix")   printf '%s\n' "$WORKSPACE_MEM" ;;
    "$prefix"-*) printf '%s\n' "${key#"$prefix"-}" ;;
    *)           return 1 ;;
  esac
}
