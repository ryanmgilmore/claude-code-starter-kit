#!/usr/bin/env bash
#
# bootstrap.sh — rebuild the ~/dev workspace on a new machine.
#
#   git clone <workspace-repo-url> ~/dev
#   ~/dev/bootstrap.sh
#
# Reads repos.tsv and clones every listed repo to its recorded path.
# Existing directories are left alone, so this is safe to re-run — use it to
# pick up repos added since the last run.
#
#   ./bootstrap.sh            clone everything
#   ./bootstrap.sh mine       only my own work
#   ./bootstrap.sh reference  only upstream reference clones
#   ./bootstrap.sh --dry-run  show what would happen
#
# Deliberately NOT git submodules. Submodules pin commits and reproduce trees
# exactly, but cost detached HEADs, unpushed submodule commits, and confusing
# status output. A flat manifest is legible and has no failure modes worth
# memorising.
#
# PATHS MATTER. Claude Code keys project memory to a project's absolute path,
# so repos must land at the same paths on every machine — hence ~/dev, and hence
# the same account name on every machine you use.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$ROOT/repos.tsv"
[ -f "$MANIFEST" ] || { echo "error: repos.tsv not found beside bootstrap.sh" >&2; exit 1; }

FILTER=""; DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1;;
    mine|reference|vendor) FILTER="$a";;
    *) echo "usage: bootstrap.sh [mine|reference|vendor] [--dry-run]" >&2; exit 1;;
  esac
done

cloned=0; skipped=0; existing=0; noremote=()

while IFS=$'\t' read -r path kind url; do
  case "$path" in ''|\#*|.) continue;; esac   # "." is this repo itself
  [ -n "$FILTER" ] && [ "$kind" != "$FILTER" ] && continue

  if [ -e "$ROOT/$path" ]; then
    printf "  exists     %s\n" "$path"; existing=$((existing+1)); continue
  fi
  if [ "$url" = "-" ]; then
    noremote+=("$path"); skipped=$((skipped+1)); continue
  fi
  if [ "$DRY" = "1" ]; then
    printf "  would clone %-44s %s\n" "$path" "$url"; cloned=$((cloned+1)); continue
  fi

  mkdir -p "$(dirname "$ROOT/$path")"
  if git clone -q "$url" "$ROOT/$path"; then
    printf "  cloned     %s\n" "$path"; cloned=$((cloned+1))
  else
    printf "  FAILED     %-44s %s\n" "$path" "$url" >&2
  fi
done < "$MANIFEST"

echo
echo "cloned: $cloned   already present: $existing   no remote yet: $skipped"

if [ "${#noremote[@]}" -gt 0 ]; then
  echo
  echo "These have no remote recorded and were NOT cloned:"
  printf '  %s\n' "${noremote[@]}"
  echo
  echo "They exist only on the machine that made them. Push each, then update"
  echo "repos.tsv:  gh repo create <name> --private --source=. --push"
fi

cat <<'EOF'

Next on a fresh machine:
  1. ~/dev/claude-config/bin/install.sh   links CLAUDE.md, settings, skills, memory
  2. log in to Claude Code fresh — never copy credentials
EOF
