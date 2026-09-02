#!/usr/bin/env bash
#
# catch-up.sh — bring this machine level with the other one.
#
#   catch-up.sh              clone what is missing, pull what is behind
#   catch-up.sh --dry-run    say what it would do, change nothing
#
# The counterpart to workspace-status.sh: that reports, this acts. Run it
# yourself, or say "catch me up" and Claude will offer to.
#
# What it does, in order:
#   1. pull ~/dev  — the manifest is how a project announces itself, so a stale
#      manifest means nothing else here can be right. Clean fast-forward only
#   2. clone what is missing, via bootstrap.sh (which skips what exists) — both
#      my own projects and the reference/ clones, since a project that arrives
#      from the other machine often registers new upstream repos it reads
#   3. pull what is behind — clean trees only, fast-forward only
#   4. link memory for anything new, via claude-config/bin/sync.sh link
#
# What it deliberately does NOT do:
#   - touch a repo with uncommitted changes. You are mid-thought there; it says
#     so and moves on
#   - merge, rebase, or resolve anything. Only fast-forwards, which cannot
#     conflict and cannot lose work
#   - commit or push your code. That stays yours
#
# So the worst case is that it reports several things it declined to do.

set -uo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$DEV/repos.tsv"
GIT=(git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5)
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

[ -f "$MANIFEST" ] || { echo "error: repos.tsv not found" >&2; exit 1; }

say()  { printf "  %s\n" "$*"; }
step() { printf "\n%s\n" "$*"; }

pulled=0; cloned=0; skipped=0; linked=0
declare -a skips=()

rows_of() { awk -F'\t' -v k="$1" '$1!~/^#/ && $1!="" && $2==k && $3!="-" {print $1}' "$MANIFEST"; }
mine_rows() { rows_of mine; }
ref_rows()  { rows_of reference; }
# Both kinds are cloned and fast-forwarded. vendor rows are left out on purpose:
# those live inside a project, are gitignored, and belong to that project's build.
sync_rows() { mine_rows; ref_rows; }

# ---------- 1. the manifest itself ----------
step "workspace repo (~/dev)"
if [ -n "$(git -C "$DEV" status --porcelain 2>/dev/null)" ]; then
  say "uncommitted changes here — not pulling. Commit them and re-run for the manifest"
  skips+=("~/dev (dirty)")
elif [ "$DRY" = "1" ]; then
  say "would pull --ff-only"
elif "${GIT[@]}" -C "$DEV" pull --ff-only --quiet 2>/dev/null; then
  say "current"
else
  say "would not fast-forward — resolve by hand, then re-run"
  skips+=("~/dev (diverged)")
fi

# ---------- 2. clone what is missing ----------
step "missing projects"
missing=0
for kind in mine reference; do
  n=0
  while read -r path; do
    [ "$path" = "." ] && continue
    [ -d "$DEV/$path" ] || n=$((n+1))
  done < <(rows_of "$kind")
  [ "$n" = "0" ] && continue
  missing=$((missing+n))

  if [ "$DRY" = "1" ]; then
    "$DEV/bootstrap.sh" "$kind" --dry-run | grep -E "would clone" | sed 's/^ */  /'
  else
    # bootstrap.sh already leaves existing directories alone and reports per repo.
    "$DEV/bootstrap.sh" "$kind" | grep -E "cloned|no remote" | sed 's/^ */  /'
    cloned=$((cloned+n))
  fi
done
[ "$missing" = "0" ] && say "none"

# ---------- 3. pull what is behind ----------
step "projects behind origin"
any=0
while read -r path; do
  [ "$path" = "." ] && continue
  dir="$DEV/$path"
  [ -d "$dir/.git" ] || continue
  git -C "$dir" rev-parse '@{u}' >/dev/null 2>&1 || continue
  n="$(git -C "$dir" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
  [ "$n" = "0" ] && continue
  any=1

  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    say "SKIP  $path — $n behind, but you have uncommitted changes"
    skips+=("$path (dirty)"); skipped=$((skipped+1)); continue
  fi
  if [ "$DRY" = "1" ]; then
    say "would pull  $path ($n commit(s))"; continue
  fi
  if "${GIT[@]}" -C "$dir" pull --ff-only --quiet 2>/dev/null; then
    say "pulled $path ($n commit(s))"; pulled=$((pulled+1))
  else
    say "SKIP  $path — would not fast-forward; you have local commits"
    skips+=("$path (diverged)"); skipped=$((skipped+1))
  fi
done < <(sync_rows)
[ "$any" = "0" ] && say "none"

# ---------- 4. link memory for anything new ----------
step "memory"
LINK="$HOME/dev/claude-config/bin/sync.sh"
if [ ! -x "$LINK" ]; then
  say "claude-config not found — skipping memory link"
elif [ "$DRY" = "1" ]; then
  say "would link any memory pulled from the other machine"
else
  out="$("$LINK" link 2>&1)"
  if [ -n "$out" ]; then printf '  %s\n' "$out"; linked=1; else say "nothing new to link"; fi
fi

# ---------- 5. the material that does not sync at all ----------
step "non-git assets"
INV="$DEV/tools/asset-inventory.sh"
if [ ! -x "$INV" ]; then
  say "asset-inventory.sh not present — skipping"
elif [ "$DRY" = "1" ]; then
  say "would re-scan this machine's inventory and diff it against the other's"
else
  "$INV" scan | sed 's/^ */  /'
  out="$("$INV" diff 2>&1)"
  if printf '%s' "$out" | grep -q "NOT here"; then
    printf '%s\n' "$out" | sed 's/^/  /'
    say "these do not move by themselves — 'asset-inventory.sh plan' writes the rsync command"
  else
    say "nothing missing in either direction"
  fi
fi

# ---------- summary ----------
printf "\n"
if [ "$DRY" = "1" ]; then
  echo "dry run — nothing changed."
else
  echo "cloned: $cloned   pulled: $pulled   skipped: $skipped"
fi
if [ "${#skips[@]}" -gt 0 ]; then
  echo
  echo "Left alone on purpose:"
  for s in "${skips[@]}"; do echo "  - $s"; done
  echo "Nothing was merged or rebased for you — those need a decision."
fi

exit 0
