#!/usr/bin/env bash
#
# new-project.sh — start a tracked, synced project in ~/dev.
#
#   tools/new-project.sh <path> [options]
#
#   tools/new-project.sh synthdev                    a new container
#   tools/new-project.sh movedev/"JX-3P editor"      a project inside one
#
# Options:
#   --container       scaffold as a workspace container (children get own repos)
#   --name <n>        GitHub repo name (default: path basename, hyphenated)
#   --no-remote       skip creating the private GitHub remote
#   --yes             don't ask before creating the remote (implied when the
#                     script has no terminal to ask on — see step 4)
#   --dry-run         show what would happen, change nothing
#
# Does the six steps that are easy to forget:
#   1. mkdir + git init
#   2. scaffold .gitignore, CLAUDE.md, .publish-exclude
#   3. initial commit
#   4. create the PRIVATE GitHub remote and push
#   5. add the row to ~/dev/repos.tsv
#   6. commit the workspace repo
#
# For a child project inside a container it also adds the child to the
# container's .gitignore and commits that, so the container's status stays
# honest.
#
# RUN THIS BEFORE ANY WORK IN THE FOLDER. The scaffolds in step 2 would other-
# wise overwrite a CLAUDE.md you wrote yourself; anything in the way is moved to
# <name>.pre-new-project.<timestamp>, which is a rescue, not a merge.
#
# Memory needs no step: claude-config/bin/adopt-memory.sh absorbs it at the end
# of the first session that writes any, and sync.sh links it on the other
# machine at its next session start.
#
# The repos.tsv row committed in step 6 is how the OTHER machine learns this
# project exists. It is pushed automatically at session start once your tree is
# clean — see tools/workspace-status.sh.

set -uo pipefail

DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$DEV/repos.tsv"

REL=""; KIND="project"; NAME=""; REMOTE=1; DRY=0; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --container) KIND="container";;
    --name) NAME="${2:?--name needs a value}"; shift;;
    --no-remote) REMOTE=0;;
    --yes|-y) ASSUME_YES=1;;
    --dry-run) DRY=1;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*) echo "unknown option: $1" >&2; exit 1;;
    *) [ -n "$REL" ] && { echo "error: give exactly one path" >&2; exit 1; }; REL="$1";;
  esac
  shift
done
[ -n "$REL" ] || { echo "usage: new-project.sh <path> [--container] [--name n] [--no-remote] [--yes] [--dry-run]" >&2; exit 1; }

REL="${REL#./}"; REL="${REL%/}"

# Accept an absolute path inside ~/dev as well as a relative one. Without this,
# `new-project.sh ~/dev/foo` silently built "$DEV/$HOME/dev/foo" — a plausible
# way to invoke it, and the failure was a mangled path rather than an error.
case "$REL" in
  "$DEV"/*)      REL="${REL#"$DEV"/}" ;;
  "$HOME"/dev/*) REL="${REL#"$HOME"/dev/}" ;;
  /*) echo "error: path must be inside ~/dev (got $REL)" >&2; exit 1 ;;
esac

DIR="$DEV/$REL"
BASE="$(basename "$REL")"
# GitHub rejects spaces; the directory name keeps them, the repo name does not.
[ -n "$NAME" ] || NAME="$(echo "$BASE" | tr ' ' '-' | tr -cd '[:alnum:]._-' | tr '[:upper:]' '[:lower:]')"

say(){ printf "  %s\n" "$*"; }
run(){ [ "$DRY" = "1" ] && { say "would: $*"; return 0; }; "$@"; }

# The scaffolds below are written with `cat >`, which overwrites without asking.
# This script is meant to run BEFORE any work in a directory, but running it on a
# folder that already has a hand-written CLAUDE.md should not destroy it — so
# anything in the way is moved aside first, using install.sh's convention.
keep(){ # keep <path>
  [ -e "$1" ] || return 0
  if [ "$DRY" = "1" ]; then say "would back up $(basename "$1")"; return 0; fi
  local bak="$1.pre-new-project.$(date +%Y%m%d%H%M%S)"
  mv "$1" "$bak" && say "backed up $(basename "$bak")  (scaffold would have overwritten it)"
}

echo "path:   $REL"
echo "kind:   $KIND"
echo "repo:   $NAME  (private)"
[ "$DRY" = "1" ] && echo "MODE:   dry run"
echo

if [ -d "$DIR/.git" ]; then echo "error: $REL is already a git repo" >&2; exit 1; fi
if grep -q "^$REL	" "$MANIFEST" 2>/dev/null; then echo "error: $REL is already in repos.tsv" >&2; exit 1; fi

run mkdir -p "$DIR"

# ---------- scaffolds ----------
if [ "$DRY" = "0" ]; then

keep "$DIR/.gitignore"
if [ "$KIND" = "container" ]; then
  cat > "$DIR/.gitignore" <<'EOF'
# Child projects each get their own repo — add them here as they are created.
# Git will not descend into them anyway; listing them keeps `status` honest.

**/.claude/settings.local.json
**/.claude/*.lock
.DS_Store
EOF
else
  cat > "$DIR/.gitignore" <<'EOF'
# Build output
dist/
build/
node_modules/
*.log

# Local environment
.env
*.local

**/.claude/settings.local.json
**/.claude/*.lock
.DS_Store
EOF
fi

keep "$DIR/.publish-exclude"
cat > "$DIR/.publish-exclude" <<'EOF'
# Paths stripped when publishing a public copy of this repo.
# Read by ~/dev/tools/publish-strip.sh. Globs, one per line.
# REVIEW THIS FILE AT PUBLISH TIME — see ~/dev/HANDOFF.md §3.
#
# Add handoffs, research notes, and any third-party documentation as they
# appear. This is a deny-list: anything not listed WOULD be published.

HANDOFF.md
EOF

if [ "$KIND" = "container" ]; then
  DESC="Workspace container. Groups related projects so they share one Claude Code
memory pool, and holds documentation spanning more than one child.

**The container is the memory unit; each child project is its own git repo.**
Those are different axes, deliberately — shared platform knowledge lives here
rather than being re-learned in every child."
else
  DESC="_One line on what this is and what it runs on._"
fi

keep "$DIR/CLAUDE.md"
cat > "$DIR/CLAUDE.md" <<EOF
# $BASE

$DESC

## Layout

_Fill in as the project takes shape._

## Publishing and repo purpose

GitHub is currently a **sync mechanism, not a publication channel** — it moves
code and accumulated knowledge between two machines (both at identical \`~/dev\`
paths). This repo is private, and nothing of mine is public.

Before any public release:

- **Evaluate every learning, handoff, and research document for removal.** They
  are written for me, not an audience, and assume context a reader will not
  have. Default to removing rather than rewriting.
- **Consider building a new repo entirely rather than stripping this one.**
- **Check for third-party material** — manuals, ROM data, datasheets. It cannot
  be redistributed and must be stripped from history, not merely deleted.
- \`.publish-exclude\` records what a strip would remove today; run it via
  \`~/dev/tools/publish-strip.sh\`. Review at publish time — it is a deny-list.
- **Never flip this repo's visibility.** Deleting a file clears only the tip;
  history would be exposed wholesale. Publishing means a *new* repo. See
  \`~/dev/HANDOFF.md\` §3.
EOF

say "scaffolded .gitignore, CLAUDE.md, .publish-exclude"
fi

# ---------- repo ----------
run git -C "$DIR" init -q
if [ "$DRY" = "0" ]; then
  git -C "$DIR" add -A
  git -C "$DIR" commit -q -m "Start $BASE

Scaffolded by ~/dev/tools/new-project.sh with the workspace conventions:
private by default, .publish-exclude deny-list, CLAUDE.md recording that
GitHub is a sync mechanism rather than a publication channel.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  say "initial commit: $(git -C "$DIR" log --oneline -1)"
fi

# ---------- parent container ----------
# A child project is its own repo, so git will not descend into it — but it does
# show up as an untracked entry in the container's `git status` until it is
# ignored. That was a manual step nobody remembered, and the noise is what makes
# a container's status stop being worth reading.
#
# Only fires when the parent is itself a repo: `foo/bar` where foo is an
# ordinary directory has no container to tell.
PARENT_REL="$(dirname "$REL")"
if [ "$PARENT_REL" != "." ] && [ -d "$DEV/$PARENT_REL/.git" ]; then
  PARENT_DIR="$DEV/$PARENT_REL"
  # Anchored to the container root and slash-suffixed: this ignores the child
  # directory specifically, not a same-named file somewhere deeper in the tree.
  RULE="/$BASE/"
  if grep -qxF "$RULE" "$PARENT_DIR/.gitignore" 2>/dev/null; then
    say "already ignored in $PARENT_REL/.gitignore"
  elif [ "$DRY" = "1" ]; then
    say "would add '$RULE' to $PARENT_REL/.gitignore and commit it"
  else
    printf '%s\n' "$RULE" >> "$PARENT_DIR/.gitignore"
    git -C "$PARENT_DIR" add .gitignore
    # Pathspec-limited so an unrelated dirty tree in the container is not swept
    # into this commit.
    if git -C "$PARENT_DIR" commit -q -m "Ignore the $BASE child repo" -- .gitignore 2>/dev/null; then
      say "ignored in $PARENT_REL/.gitignore: $(git -C "$PARENT_DIR" log --oneline -1)"
    else
      say "added '$RULE' to $PARENT_REL/.gitignore — commit it yourself"
    fi
  fi
fi

# ---------- remote ----------
URL="-"
if [ "$REMOTE" = "1" ]; then
  if [ "$DRY" = "1" ]; then
    say "would: gh repo create $NAME --private --source=$REL --push"
    URL="https://github.com/<you>/$NAME.git"
  else
    echo
    # A run with no terminal (Claude Code, a script, CI) used to fall through
    # here with an empty reply from EOF and silently take the "skipped" branch,
    # leaving a '-' in the manifest and a project on one machine only. The
    # remote is the point of the script, so no-tty means yes; --no-remote is
    # how you decline, and it is checked above.
    if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
      reply=y
      [ -t 0 ] || say "no terminal to ask on — creating the remote (--no-remote declines)"
    else
      read -r -p "  Create PRIVATE GitHub repo '$NAME' and push? [y/N] " reply
    fi
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      # Keep gh's own diagnostics. Discarding them left "gh repo create failed"
      # as the whole story, which is the same message for a name collision, an
      # expired token, and no network — three problems with three different
      # fixes. Indent it so it reads as detail under the failure line.
      if out="$(cd "$DIR" && gh repo create "$NAME" --private --source=. --push 2>&1)"; then
        URL="$(git -C "$DIR" remote get-url origin 2>/dev/null || echo -)"
        say "pushed to $URL"
      else
        say "gh repo create failed — recorded with no remote; push later"
        printf '%s\n' "$out" | sed '/^[[:space:]]*$/d; s/^/    /' >&2
        say "retry: cd \"$DIR\" && gh repo create $NAME --private --source=. --push"
        say "then put the URL in $MANIFEST (the row is written with '-')"
      fi
    else
      say "skipped remote — recorded as '-' in repos.tsv"
    fi
  fi
fi

# ---------- manifest ----------
if [ "$DRY" = "1" ]; then
  say "would add to repos.tsv:  $REL	mine	$URL"
else
  printf '%s\t%s\t%s\n' "$REL" "mine" "$URL" >> "$MANIFEST"
  # keep it sorted, comments first
  python3 - "$MANIFEST" <<'PY'
import sys
p=sys.argv[1]; lines=open(p).read().splitlines()
head=[l for l in lines if l.startswith('#') or not l.strip()]
rows=sorted({l for l in lines if l and not l.startswith('#')}, key=str.lower)
open(p,'w').write("\n".join(head+rows)+"\n")
PY
  git -C "$DEV" add repos.tsv
  git -C "$DEV" commit -q -m "Add $REL to the manifest

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  say "manifest updated and workspace repo committed"
fi

echo
if [ "$URL" = "-" ] && [ "$DRY" = "0" ]; then
  echo "No remote yet — this project exists on one machine only. When ready:"
  echo "  cd \"$DIR\" && gh repo create $NAME --private --source=. --push"
  echo "  then update the URL in ~/dev/repos.tsv"
fi
echo "Memory needs no action: it is absorbed automatically at the end of the"
echo "first session that writes any (claude-config/bin/adopt-memory.sh)."
