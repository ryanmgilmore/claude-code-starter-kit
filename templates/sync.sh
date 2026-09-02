#!/usr/bin/env bash
#
# sync.sh — keep claude-config converged across machines.
#
#   sync.sh pull    capture local work, rebase onto the remote (session start)
#   sync.sh push    capture local work, push it (session end)
#
# Invoked from the SessionStart / SessionEnd hooks in settings.json.
#
# Design rules, in order of importance:
#   1. NEVER fail. A hook that errors or hangs breaks session startup, which is
#      far worse than memory being briefly stale. Every path exits 0.
#   2. Never block for long. Git is given a low-speed timeout so a dead network
#      gives up in seconds rather than hanging.
#   3. Never destroy work. On anything ambiguous — a conflict, a half-finished
#      merge — stop and leave the working tree exactly as it was found.
#   4. No remote is a valid state. Without one this makes local commits only.
#
# Both verbs capture first, then talk to the network. Capturing at session START
# as well as end is what makes the handoff survive a session that never ended
# cleanly: a crash, a closed terminal, or a `kill` skips SessionEnd entirely, and
# without this that memory would sit uncommitted until someone noticed.

REPO="$HOME/dev/claude-config"
cd "$REPO" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

GITDIR="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0

# Give up on a stalled network quickly rather than hanging the session.
GIT=(git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5)

# Where a failure is recorded so the NEXT session start can report it. Lives in
# .git/ deliberately: it describes this machine's predicament, and syncing it to
# the other machine would be nonsense.
STATUS="$GITDIR/claude-sync-status"

# Set alongside $STATUS when the recorded failure is one that later local state
# can DISPROVE — see report(). Markers without it are sticky: they describe
# something no amount of converging can answer.
STATUS_VERIFIABLE="$GITDIR/claude-sync-status-verifiable"

# The one path in this repo that names something in ANOTHER repo. Declared once,
# asserted by test/workspace-test.sh against the real ~/dev, so renaming it there
# without updating it here fails a test instead of silently changing behaviour.
WORKSPACE_TOOL="tools/workspace-status.sh"

# Key derivation and the workspace root live in one place, so this works on a
# machine whose workspace is not at ~/dev. Absent, everything else still runs.
CLAUDE_CONFIG_REPO="$REPO"
# shellcheck source=lib-paths.sh
. "$REPO/bin/lib-paths.sh" 2>/dev/null || exit 0

has_remote() { git remote get-url origin >/dev/null 2>&1; }
machine()    { scutil --get ComputerName 2>/dev/null || hostname -s; }
stamp()      { date +%Y-%m-%d\ %H:%M; }

note()   { printf '%s\n' "claude-config: $*" >&2; }
# Stamped, because a marker read days later is otherwise indistinguishable from
# one written this morning, and the two call for different reactions.
mark()   { printf '%s\n' "claude-config: $* [$(stamp)]" >"$STATUS" 2>/dev/null; note "$*"; }
# As mark(), but the claim is checkable later: it says local work needs hands.
mark_diverged() { mark "$@"; : > "$STATUS_VERIFIABLE" 2>/dev/null; }
unmark() { rm -f "$STATUS" "$STATUS_VERIFIABLE" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Only one sync at a time.
#
# Two Claude sessions can be open at once, and a SessionEnd firing in the middle
# of another session's rebase is how a repo ends up mid-operation. mkdir is
# atomic on every filesystem that matters here; flock(1) is not on macOS.
# ---------------------------------------------------------------------------
LOCK="$GITDIR/claude-sync.lock"
if [ -d "$LOCK" ]; then
  # A lock older than five minutes outlived whatever made it (git has a 5s
  # network timeout, so nothing legitimate takes that long).
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
  else
    exit 0   # another session is syncing; it will carry this work too
  fi
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# Refuse to touch a working tree that a human is part-way through.
# ---------------------------------------------------------------------------
in_progress() {
  [ -e "$GITDIR/MERGE_HEAD" ] && return 0
  [ -e "$GITDIR/CHERRY_PICK_HEAD" ] && return 0
  [ -d "$GITDIR/rebase-merge" ] && return 0
  [ -d "$GITDIR/rebase-apply" ] && return 0
  [ -n "$(git ls-files --unmerged 2>/dev/null)" ]   # unresolved conflicts
}

# ---------------------------------------------------------------------------
# capture — commit whatever this machine has produced.
#
# Split in two so `git log` stays readable. Everything used to land under a
# "memory: sync" message, including edits to the hooks and scripts themselves,
# which made the history unable to answer "when did the sync behaviour change?"
# Memory is data this script owns; anything else is work a human was doing, and
# is committed under its own message so it can be reworded later.
# ---------------------------------------------------------------------------
capture() {
  if in_progress; then
    mark "merge or rebase in progress — not committing (finish it, then re-run)"
    return 1
  fi

  # Absorb memory for any project that did not exist last time this ran.
  "$REPO/bin/adopt-memory.sh" 2>&1 | grep -v '^  skip' || true

  # Re-attach anything tooling detached, before staging, so the merge is captured.
  heal_links

  # What counts as data rather than configuration: memory, task lists, and session
  # digests. All are written BY Claude Code or about it, change every session, and
  # mean nothing as a "somebody edited the config" signal — grouping them with
  # configuration made `config: sync` fire every session and stop meaning anything.
  local -a data=()
  [ -d "$REPO/memory" ]  && data+=(memory)
  [ -e "$REPO/tasks" ]   && data+=(tasks)
  [ -d "$REPO/digests" ] && data+=(digests)

  if [ "${#data[@]}" -gt 0 ]; then
    git add -A -- "${data[@]}" 2>/dev/null
    git diff --cached --quiet 2>/dev/null || \
      git commit --quiet -m "memory: sync from $(machine) $(stamp)" 2>/dev/null
  fi

  git add -A 2>/dev/null
  git diff --cached --quiet 2>/dev/null || \
    git commit --quiet -m "config: sync from $(machine) $(stamp)" 2>/dev/null

  return 0
}

# ---------------------------------------------------------------------------
# heal_links — repair symlinks that tooling replaced with real files.
#
# ~/.claude/settings.json is the known case: anything that saves by atomic replace
# (temp file + rename) leaves a regular file where the symlink was, silently
# detaching it from this repo.
#
# Detached links are **reported, not moved** — silently relocating a file that
# somebody's tooling is actively rewriting is how you lose what it was writing.
#
# The one thing this function does act on is the migration away from syncing
# history.jsonl: a machine that synced it before now has a symlink into this repo
# pointing at a file that no longer exists, and Claude Code appends to that path
# constantly. That link is restored to a local file, with its last synced contents
# recovered from git so nothing typed on that machine is lost.
# ---------------------------------------------------------------------------
heal_links() {
  local claude="$HOME/.claude" detached=""

  # history.jsonl is no longer synced. A machine that synced it before has a
  # symlink pointing into this repo at a file that no longer exists — and Claude
  # Code appends to that path constantly, so a dangling link is not something to
  # leave lying around. Restore the last synced contents from git, so nothing that
  # machine typed is lost, and hand the file back as a local one.
  # Any symlink at this path pointing into the repo needs migrating, whether or not
  # its target still exists. Both states occur: dangling right after the pull that
  # removed the file, and *re-created* if Claude Code appended through the dangling
  # link in between — writing through a symlink creates the target, which would put
  # an untracked history.jsonl back inside the repo.
  local hist="$claude/history.jsonl"
  if [ -L "$hist" ] && [ "$(readlink "$hist" 2>/dev/null)" = "$REPO/history.jsonl" ]; then
    local del rescued=0 stray=""
    # Anything written through the link since the removal is real history: keep it.
    [ -f "$REPO/history.jsonl" ] && stray="$(cat "$REPO/history.jsonl" 2>/dev/null)"
    del="$(git log --diff-filter=D --format=%H -1 -- history.jsonl 2>/dev/null)"
    rm -f "$hist" 2>/dev/null
    if [ -n "$del" ] && git show "$del^:history.jsonl" > "$hist" 2>/dev/null; then
      rescued="$(wc -l < "$hist" 2>/dev/null | tr -d ' ')"
    fi
    if [ -n "$stray" ]; then
      printf '%s\n' "$stray" >> "$hist" 2>/dev/null
      # De-duplicate: the rescued copy and the stray copy overlap by construction.
      local tmp; tmp="$(mktemp)" && awk '!seen[$0]++' "$hist" > "$tmp" 2>/dev/null && \
        mv "$tmp" "$hist" 2>/dev/null
      rescued="$(wc -l < "$hist" 2>/dev/null | tr -d ' ')"
    fi
    rm -f "$REPO/history.jsonl" 2>/dev/null    # never let it back into the repo
    if [ "${rescued:-0}" != "0" ]; then
      echo "claude-config: history.jsonl is machine-local again — restored $rescued line(s) from git"
    else
      echo "claude-config: history.jsonl is machine-local again — Claude Code will start a fresh one"
    fi
  fi

  # Detached symlinks: report only.
  local p
  for p in "$claude/settings.json" "$claude/CLAUDE.md" "$claude/skills" "$claude/tasks"; do
    [ -e "$p" ] || continue
    [ -L "$p" ] && continue
    detached="$detached ${p##*/}"
  done
  [ -n "$detached" ] && \
    mark "no longer symlinked into claude-config:$detached — re-run bin/install.sh (it backs up first)"
  return 0
}

# ---------------------------------------------------------------------------
# link_pass — link memory this machine pulled but has never linked.
#
# install.sh links what exists when it runs. A project created on the OTHER
# machine arrives later, as a plain directory in memory/ — and nothing points at
# it here. The first session in that project then writes memory to a real
# directory, and adopt-memory.sh correctly refuses to merge two populated
# copies. The right answer was never "merge": it was "link it before anything
# writes there".
#
# So this runs at session start, after the rebase, and only ever acts where
# there is nothing to lose: no symlink and no real directory. Populated real
# directories are left to the conflict path they belong to.
# ---------------------------------------------------------------------------
link_pass() {
  local name mem linked=0

  shopt -s nullglob
  for dir in "$REPO"/memory/*/; do
    name="$(basename "$dir")"
    mem="$HOME/.claude/projects/$(key_for_name "$name")/memory"

    # Anything already there — symlink, dangling symlink, or real directory —
    # is somebody else's business.
    if [ -e "$mem" ] || [ -L "$mem" ]; then continue; fi

    mkdir -p "$(dirname "$mem")" 2>/dev/null || continue
    if ln -s "$REPO/memory/$name" "$mem" 2>/dev/null; then
      linked=$((linked+1))
    fi
  done

  [ "$linked" -gt 0 ] && \
    echo "claude-config: linked $linked project memory dir(s) from the other machine"
  return 0
}

# ---------------------------------------------------------------------------
# rebase_onto_remote — fetch and replay local commits on top.
#
# A conflicted rebase left in place would break every later session, so back out
# and keep the local copy. The marker means the next session start says so out
# loud instead of failing quietly forever.
# ---------------------------------------------------------------------------
rebase_onto_remote() {
  has_remote || return 0
  if "${GIT[@]}" pull --rebase --autostash --quiet 2>/dev/null; then
    return 0
  fi
  git rebase --abort 2>/dev/null
  mark_diverged "pull failed — keeping local copy. Resolve by hand: cd ~/dev/claude-config && git pull --rebase"
  return 1
}

# ---------------------------------------------------------------------------
# push_now — push, and handle the other machine having pushed meanwhile.
#
# This is the failure that actually loses a handoff: a session that ran for
# hours pulled at start, the other Mac pushed since, and the session-end push is
# rejected as non-fast-forward. Retrying once after a rebase converges the
# ordinary case; anything left is a real conflict and gets reported.
# ---------------------------------------------------------------------------
push_now() {
  has_remote || return 0
  git rev-parse '@{u}' >/dev/null 2>&1 || return 0   # no upstream set yet

  # Nothing local to send: skip the round-trip entirely. This matters at session
  # START, which is the latency the user actually feels, and where the common
  # case is having nothing to push. Converged also means any older failure
  # marker is obsolete.
  if [ "$(git rev-list --count '@{u}'..HEAD 2>/dev/null || echo 0)" = "0" ]; then
    unmark
    return 0
  fi

  if "${GIT[@]}" push --quiet 2>/dev/null; then unmark; return 0; fi

  if rebase_onto_remote && "${GIT[@]}" push --quiet 2>/dev/null; then
    unmark
    return 0
  fi

  local ahead
  ahead="$(git rev-list --count '@{u}'..HEAD 2>/dev/null || echo '?')"
  mark_diverged "push failed — $ahead local commit(s) not on the remote yet"
  return 1
}

# ---------------------------------------------------------------------------
# bootstrap_workspace — the one time this script looks outside its own repo.
#
# ~/dev is pulled by the workspace tool named in $WORKSPACE_TOOL, which ARRIVES by
# that pull. A machine that does not have the tooling yet therefore cannot get
# it: settings.json syncs the hook automatically, the hook no-ops silently on a
# missing script, and that machine stays behind until somebody remembers a manual
# `git -C ~/dev pull`. Every future workspace tool would have the same gap.
#
# So this closes it, as narrowly as possible:
#
#   - only when $WORKSPACE_TOOL is MISSING, and only once per machine ever
#   - only with a clean tree, and only --ff-only, which cannot conflict
#   - never a commit, never a push
#
# Yes, this crosses the boundary that otherwise keeps this script inside
# claude-config. That is the point: it is the bootstrap case, and nothing else
# can perform it.
# ---------------------------------------------------------------------------
bootstrap_workspace() {
  local dev="$HOME/dev" marker="$GITDIR/workspace-bootstrapped"

  # Once per machine, ever. Without this the guard below is a *filename*: rename
  # WORKSPACE_TOOL and the "already installed" test never passes again, so this
  # would pull ~/dev on every session start forever — a permanent boundary
  # crossing, silent, because the confirmation message keys off the same name.
  # The marker makes the one-time promise true regardless of what anything is
  # called. It lives in .git/ because it describes this machine.
  [ -e "$marker" ] && return 0

  [ -e "$dev/$WORKSPACE_TOOL" ] && return 0     # already installed
  [ -d "$dev/.git" ] || return 0
  git -C "$dev" remote get-url origin >/dev/null 2>&1 || return 0
  [ -n "$(git -C "$dev" status --porcelain 2>/dev/null)" ] && return 0   # dirty

  if "${GIT[@]}" -C "$dev" pull --ff-only --quiet 2>/dev/null; then
    : > "$marker" 2>/dev/null
    if [ -e "$dev/$WORKSPACE_TOOL" ]; then
      echo "claude-config: pulled ~/dev to install the workspace tooling (one time only)"
    else
      # The pull worked and the tool still is not there, so the expectation is
      # wrong — it was renamed, moved, or never existed. Reported rather than
      # retried: silently pulling another repo forever is how this went wrong in
      # the first place, and the whole point of the marker is to stop at one.
      mark "expected $WORKSPACE_TOOL in ~/dev after bootstrapping and it is not there — has the workspace tooling moved?"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# report — say, at session start, what an earlier session could not fix.
#
# SessionEnd output goes nowhere anybody reads; session start is surfaced. A
# divergence that is never reported is one that is discovered as data loss.
#
# But a marker outlives its cause easily. A fetch that failed once — a dropped
# network at startup — writes one, the network comes back, and every session
# afterwards repeats advice that now does nothing: `git pull --rebase` answers
# "Already up to date" and the reader cannot tell a live problem from a cured
# one. A warning that cannot be distinguished from a false one stops being read.
#
# So a verifiable marker is checked before it is believed. The check is local and
# costs no network: these markers say local work needs hands, and hands are
# needed only while a rebase is unfinished or this machine holds commits the
# remote has not got. Neither, and the marker is answering a question that is no
# longer being asked.
#
# It is deliberately conservative. Anything ambiguous — no upstream, a count git
# will not give — is left alone and still reported, because the cost of a stale
# warning is irritation and the cost of a dropped one is a lost handoff.
# ---------------------------------------------------------------------------
marker_is_stale() {
  [ -e "$STATUS_VERIFIABLE" ] || return 1        # sticky: nothing can disprove it
  [ -d "$GITDIR/rebase-merge" ] && return 1
  [ -d "$GITDIR/rebase-apply" ] && return 1
  git rev-parse '@{u}' >/dev/null 2>&1 || return 1
  [ "$(git rev-list --count '@{u}'..HEAD 2>/dev/null || echo '?')" = "0" ]
}

report() {
  [ -s "$STATUS" ] || return 0
  if marker_is_stale; then unmark; return 0; fi
  cat "$STATUS"
  return 0
}

case "${1:-}" in
  pull)
    # link_pass runs last on purpose: it only creates symlinks outside the repo,
    # so it is safe after the push, and it needs the rebase to have landed first.
    if capture; then
      # Sequential, NOT `rebase_onto_remote && push_now`. A failed fetch says
      # nothing about whether the push would work, and the two failures are not
      # the same size: a stale local copy costs a session of freshness, while
      # local commits that never leave this machine are how a handoff is lost.
      # push_now handles a rejection by rebasing and retrying, so trying it after
      # a failed pull is safe and occasionally the thing that saves the work.
      rebase_onto_remote
      push_now
      link_pass
    fi
    bootstrap_workspace    # unrelated to this repo's state, so outside the guard
    report
    ;;

  push)
    capture && push_now
    ;;

  link)     # link memory pulled from the other machine; used by catch-up.sh
    link_pass
    ;;

  status)   # for a human: what is this machine's sync state?
    report
    git status --short --branch
    ;;

  *)
    # exit 1, not 0: sync.sh is driven by hooks, so a typo'd subcommand that
    # reported success would be a sync that silently never ran.
    echo "usage: sync.sh {pull|push|link|status}" >&2
    exit 1
    ;;
esac

exit 0
