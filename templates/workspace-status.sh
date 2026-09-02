#!/usr/bin/env bash
#
# workspace-status.sh — say what is out of sync between the two machines.
#
#   workspace-status.sh report    fast, cached, silent when clean (session hook)
#   workspace-status.sh refresh   fetch every repo, update the cache (background)
#   workspace-status.sh now       refresh, then report — a live answer
#
# Wired into the SessionStart hook. Design rules, in order:
#
#   1. NEVER fail, never hang. Every path exits 0; git gets a short network
#      timeout. A broken hook costs more than a stale report.
#   2. SILENT WHEN CLEAN. A report that prints every session becomes wallpaper,
#      and then a real warning goes unread. If it says something, it means
#      something.
#   3. NEVER touch project code. It reports, and Claude offers to act. The one
#      exception is the workspace repo itself — see converge() below.
#   4. Answer instantly. Knowing whether 19 repos are behind needs 19 fetches,
#      which cannot happen at session start. So `report` reads local refs (which
#      is instant) and `refresh` runs detached to make those refs current. The
#      report is therefore at most one session stale, and says so when the
#      cache is old.
#
# Everything printed goes to STDOUT deliberately: SessionStart stdout is added
# to Claude's context, so Claude can offer to fix what this finds.

set -uo pipefail

# -P so the comparison in new_project_check is against a physical path. On macOS
# /var is a symlink to /private/var, so a logical path and a resolved one never
# match and the check would silently never fire.
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MANIFEST="$DEV/repos.tsv"
GITDIR="$DEV/.git"
STAMP="$GITDIR/workspace-fetch-stamp"
LOCK="$GITDIR/workspace-fetch.lock"
STALE_MIN=90        # cache older than this is called out in the report
GIT=(git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5)

[ -f "$MANIFEST" ] || exit 0

say() { printf 'workspace: %s\n' "$*"; }

# Rows I own that have a remote recorded. Reference and vendor clones are other
# people's code — reported only by `now`, never nagged about at session start.
mine_rows() { awk -F'\t' '$1!~/^#/ && $1!="" && $2=="mine" && $3!="-" {print $1"\t"$3}' "$MANIFEST"; }

dirty()   { [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }
upstream(){ git -C "$1" rev-parse '@{u}' >/dev/null 2>&1; }
behind()  { git -C "$1" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0; }
ahead()   { git -C "$1" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0; }

# ---------------------------------------------------------------------------
# converge — the one repo this script may change: ~/dev itself.
#
# Justified because it is how a project announces itself. new-project.sh commits
# a repos.tsv row, and until that row reaches the other machine, the other
# machine cannot know the project exists — so detection would be blind without
# it. Bounded hard:
#
#   pull  only with a clean tree, and only --ff-only, which cannot conflict
#   push  only with a clean tree and only when ahead. Never --force
#   commit NEVER. Uncommitted doc prose is yours until you commit it
#
# A dirty tree is reported, not touched.
# ---------------------------------------------------------------------------
converge() {
  upstream "$DEV" || return 0

  # One synchronous fetch, of one repo. Everything else waits for the background
  # pass, but the manifest cannot: a project announces itself through a
  # repos.tsv row, and reading a stale ref would mean never noticing it. This
  # costs a fraction of a second and is the difference between detection working
  # and detection being decorative.
  "${GIT[@]}" -C "$DEV" fetch --quiet 2>/dev/null

  if dirty "$DEV"; then
    local a; a="$(ahead "$DEV")"
    [ "$a" != "0" ] && say "~/dev has $a unpushed commit(s) and a dirty tree — not pushed for you"
    manifest_warning
    return 0
  fi

  if [ "$(behind "$DEV")" != "0" ]; then
    if "${GIT[@]}" -C "$DEV" pull --ff-only --quiet 2>/dev/null; then
      say "pulled ~/dev (docs and repos.tsv are now current)"
    else
      say "~/dev is behind and would not fast-forward — resolve by hand"
    fi
  fi

  if [ "$(ahead "$DEV")" != "0" ]; then
    local n; n="$(ahead "$DEV")"
    if "${GIT[@]}" -C "$DEV" push --quiet 2>/dev/null; then
      say "pushed ~/dev ($n commit(s)) — the other machine can see them now"
    else
      say "~/dev has $n unpushed commit(s); push failed"
      manifest_warning
    fi
  fi
}

# A manifest row that never left this machine is the one unpushed change with a
# consequence beyond this repo: the other Mac cannot learn the project exists.
manifest_warning() {
  git -C "$DEV" diff --name-only '@{u}..HEAD' 2>/dev/null | grep -qx 'repos.tsv' || return 0
  say "  ...including new repos.tsv rows — the other machine cannot see those projects yet"
}

# ---------------------------------------------------------------------------
# refresh — make local refs current so `report` can be instant.
# ---------------------------------------------------------------------------
refresh() {
  if [ -d "$LOCK" ]; then
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      rmdir "$LOCK" 2>/dev/null
    else
      exit 0   # a fetch is already running
    fi
  fi
  mkdir -p "$GITDIR" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || exit 0
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT

  local path url n=0
  while IFS=$'\t' read -r path url; do
    [ "$path" = "." ] && path=""
    local dir="$DEV${path:+/$path}"
    [ -d "$dir/.git" ] || continue
    "${GIT[@]}" -C "$dir" fetch --quiet 2>/dev/null && n=$((n+1))
  done < <(mine_rows)

  # Reference clones matter for `now`, and cost nothing extra here.
  for dir in "$DEV"/reference/*/; do
    [ -d "$dir/.git" ] || continue
    "${GIT[@]}" -C "$dir" fetch --quiet 2>/dev/null && n=$((n+1))
  done

  date +%s > "$STAMP" 2>/dev/null
  [ "${VERBOSE:-0}" = "1" ] && say "fetched $n repo(s)"
  return 0
}

# Start a fetch that outlives this hook. Nothing waits on it; its results are
# read by the NEXT report.
refresh_detached() {
  [ -d "$LOCK" ] && return 0
  nohup "$0" refresh >/dev/null 2>&1 &
  disown 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# new_project_check — "you are working somewhere that syncs nowhere".
#
# A folder created by hand in ~/dev is not a git repo and has no repos.tsv row,
# so nothing in it reaches the other machine and its memory has nowhere to live.
# new-project.sh fixes that in one command, but only if you remember it exists —
# and it must run BEFORE any work, because the scaffolds would overwrite a
# CLAUDE.md written by hand.
#
# Scoped deliberately to a new TOP-LEVEL folder. A new child project inside a
# container (movedev/"JX-3P editor") cannot be told apart from an ordinary
# subdirectory of that container's repo — both are non-repo folders inside a
# repo — so guessing there would fire on every src/ and vendor/ and destroy the
# silence that makes this report worth reading.
# ---------------------------------------------------------------------------
new_project_check() {
  local dir="${1:-}" rel top
  [ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  [ -d "$dir" ] || return 0
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 0
  case "$dir" in
    "$DEV") return 0 ;;          # the workspace itself
    "$DEV"/*) rel="${dir#"$DEV"/}" ;;
    *) return 0 ;;               # outside ~/dev entirely
  esac

  top="${rel%%/*}"
  case "$top" in
    reference|other|archive|claude-config|docs|tools|test) return 0 ;;
  esac

  [ -d "$DEV/$top/.git" ] && return 0                          # already a repo
  grep -q "^$top	" "$MANIFEST" 2>/dev/null && return 0        # already tracked

  say "$top/ is not a git repo and has no repos.tsv row — nothing here syncs, and"
  say "  its memory has nowhere to live. Ask me to set it up, or run:"
  say "    ~/dev/tools/new-project.sh \"$top\""
  return 0
}

# ---------------------------------------------------------------------------
# ignored_source_check — a workspace file git cannot see is a file that never syncs.
#
# ~/dev's .gitignore ignores `/*` and whitelists back, which is right: it makes it
# impossible to sweep a whole project in by accident. The failure mode is the
# mirror image — a script or doc that no whitelist covers is invisible to git,
# never commits, never reaches the other machine, and NOTHING SAYS SO. That
# happened three times in one day, the last time to a file the starter kit had
# already been told to copy.
#
# The .gitignore now whitelists directories rather than individual files, which
# removes the recurring step. This is the backstop for the day those rules
# regress: it checks the workspace's own source files — never project trees, which
# are ignored by design — and is silent when they are all visible.
#
# It catches UNTRACKED-and-ignored, which is the harmful combination and exactly
# what bit three times. `git check-ignore` deliberately says nothing about files
# already tracked, and that is right: a tracked file keeps syncing whatever a
# later rule says. The silent loss is a file git has never seen.
# ---------------------------------------------------------------------------
ignored_source_check() {
  local -a hidden=()
  local f

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$DEV" check-ignore -q "$f" 2>/dev/null && hidden+=("${f#"$DEV"/}")
  done < <(
    find "$DEV" -maxdepth 1 -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tsv' \) 2>/dev/null
    find "$DEV/tools" "$DEV/test" "$DEV/docs" "$DEV/assets" -type f \
      \( -name '*.sh' -o -name '*.md' -o -name '*.tsv' \) 2>/dev/null
  )

  if [ "${#hidden[@]}" -gt 0 ]; then
    say "${#hidden[@]} workspace file(s) are gitignored, so they will never sync:"
    printf 'workspace:   %s\n' "${hidden[@]}"
    say "  ~/dev/.gitignore ignores /* and whitelists back — add the directory, not the file"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# current_check — the repo you are about to work in, checked for real.
#
# Everything else is answered from local refs and made current by a detached
# fetch, because fetching all of mine (29 and growing) costs tens of seconds.
# But the repo this session is IN is
# different in kind: it is the one whose staleness you are about to act on, where
# being a session behind means starting work on top of an old tree. One fetch is
# a fraction of a second, so it is checked synchronously and reported first.
#
# It still only ever reports. Pulling project code stays a decision.
# ---------------------------------------------------------------------------
CURRENT_REL=""

# The enclosing git repo of a directory, as a path relative to ~/dev. For a child
# project this is the child, not its container — the nearest .git wins.
enclosing_repo() {
  local dir="${1:-}" p
  [ -n "$dir" ] || dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  [ -d "$dir" ] || return 0
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 0
  case "$dir" in
    "$DEV") return 0 ;;                       # workspace repo: converge()'s job
    "$DEV"/*) ;;
    *) return 0 ;;
  esac
  case "${dir#"$DEV"/}" in
    reference/*|other/*|archive/*|claude-config/*) return 0 ;;   # not mine
  esac

  p="$dir"
  while [ "$p" != "$DEV" ] && [ "$p" != "/" ]; do
    if [ -d "$p/.git" ]; then printf '%s\n' "${p#"$DEV"/}"; return 0; fi
    p="$(dirname "$p")"
  done
  return 0
}

current_check() {
  CURRENT_REL="$(enclosing_repo "${1:-}")"
  [ -n "$CURRENT_REL" ] || return 0

  local dir="$DEV/$CURRENT_REL" b a
  upstream "$dir" || return 0
  "${GIT[@]}" -C "$dir" fetch --quiet 2>/dev/null

  b="$(behind "$dir")"; a="$(ahead "$dir")"

  if [ "$b" != "0" ]; then
    if dirty "$dir"; then
      say "$CURRENT_REL is $b commit(s) behind origin AND has uncommitted changes"
      say "  commit or stash first — pulling now would be a merge, not a fast-forward"
    else
      say "$CURRENT_REL is $b commit(s) behind origin — and it is what you are working in"
      say "  ask me to pull it, or: git -C \"\$HOME/dev/$CURRENT_REL\" pull --ff-only"
    fi
  fi
  [ "$a" != "0" ] && say "$CURRENT_REL has $a commit(s) not pushed to the other machine"
  return 0
}

# ---------------------------------------------------------------------------
# report — local only, instant, silent when there is nothing to say.
# ---------------------------------------------------------------------------
report() {
  local path url dir
  local -a missing=() behind_list=() dirty_list=() unpushed=()

  while IFS=$'\t' read -r path url; do
    [ "$path" = "." ] && continue             # the workspace repo, handled by converge
    # claude-config commits and pushes itself, so it is dirty mid-session by
    # design. Reporting that would print something every session and turn this
    # report into wallpaper. It reports its own trouble via sync.sh status.
    [ "$path" = "claude-config" ] && continue
    # The current project already has its own, freshly-fetched line above.
    [ -n "$CURRENT_REL" ] && [ "$path" = "$CURRENT_REL" ] && continue
    dir="$DEV/$path"
    if [ ! -d "$dir" ]; then
      missing+=("$path")
      continue
    fi
    [ -d "$dir/.git" ] || continue
    dirty "$dir" && dirty_list+=("$path")
    upstream "$dir" || continue
    [ "$(behind "$dir")" != "0" ] && behind_list+=("$path ($(behind "$dir"))")
    [ "$(ahead  "$dir")" != "0" ] && unpushed+=("$path ($(ahead "$dir"))")
  done < <(mine_rows)

  if [ "${#missing[@]}" -gt 0 ]; then
    say "${#missing[@]} project(s) here on the other machine but not this one: ${missing[*]}"
    say "  ask me to catch you up, or run: ~/dev/tools/catch-up.sh"
  fi
  [ "${#behind_list[@]}" -gt 0 ] && say "behind origin: ${behind_list[*]}"
  [ "${#unpushed[@]}"    -gt 0 ] && say "unpushed: ${unpushed[*]}"
  [ "${#dirty_list[@]}"  -gt 0 ] && say "uncommitted changes: ${dirty_list[*]}"

  # Only worth mentioning when there was something to be wrong about.
  if [ "${#behind_list[@]}" -gt 0 ] || [ "${#missing[@]}" -gt 0 ]; then
    if [ -f "$STAMP" ]; then
      local age=$(( ( $(date +%s) - $(cat "$STAMP" 2>/dev/null || echo 0) ) / 60 ))
      [ "$age" -gt "$STALE_MIN" ] && say "  (last fetch ${age}m ago — run 'workspace-status.sh now' for a live answer)"
    else
      say "  (no fetch recorded yet — first run; 'workspace-status.sh now' answers live)"
    fi
  fi
  return 0
}

case "${1:-report}" in
  report)  ignored_source_check; new_project_check "${2:-}"; current_check "${2:-}"; converge; report; refresh_detached ;;
  refresh) refresh ;;
  now)     ignored_source_check; new_project_check "${2:-}"; current_check "${2:-}"; VERBOSE=1 refresh; converge; report ;;
  *)       echo "usage: workspace-status.sh {report|refresh|now} [dir]" >&2; exit 1 ;;
esac

exit 0
