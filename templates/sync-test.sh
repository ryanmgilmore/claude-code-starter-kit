#!/usr/bin/env bash
#
# sync-test.sh — two-machine simulation for sync.sh / adopt-memory.sh.
#
# Builds a bare repo standing in for GitHub plus two fake homes, then plays out
# the handoff: adoption, the commit split, a stale push, a crashed session, a
# real conflict, a half-finished merge, two sessions racing, and no remote.
#
# Run it after touching either script. It writes only inside its own scratch
# directory and never touches the real ~/.claude.
#
#   ./test/sync-test.sh
#
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${TMPDIR:-/tmp}/claude-config-sync-test.$$"
trap 'rm -rf "$S"' EXIT
U="$(id -un)"
rm -rf "$S"; mkdir -p "$S"

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
# pipefail is right for this harness's setup code and wrong for assertions: a
# `git log | grep -q` pipeline exits early by design, git dies of SIGPIPE, and
# pipefail then calls a correct assertion a failure — intermittently, depending
# on which process wins. So assertions run with it off.
check(){ set +o pipefail; if eval "$2"; then ok "$1"; else bad "$1"; fi; set -o pipefail; }

# --- the "remote" -----------------------------------------------------------
git init --bare -q -b main "$S/remote.git"

# --- seed a repo with the real scripts --------------------------------------
seed="$S/seed"
mkdir -p "$seed/bin" "$seed/memory"
cp "$SRC/bin/sync.sh" "$SRC/bin/adopt-memory.sh" "$SRC/bin/install.sh" \
   "$SRC/bin/lib-paths.sh" "$SRC/bin/digest.sh" "$seed/bin/"
cp "$SRC/path-map.tsv" "$SRC/.gitignore" "$seed/" 2>/dev/null || true
chmod +x "$seed"/bin/*.sh
printf 'seed\n' > "$seed/CLAUDE.md"
printf '{}\n' > "$seed/settings.json"
mkdir -p "$seed/skills"; printf 'x\n' > "$seed/skills/.keep"
git -C "$seed" init -q -b main
git -C "$seed" -c user.email=t@t -c user.name=t add -A
git -C "$seed" -c user.email=t@t -c user.name=t commit -qm seed
git -C "$seed" remote add origin "$S/remote.git"
git -C "$seed" push -q origin main

# --- two machines -----------------------------------------------------------
mk_machine() { # mk_machine <name>
  local h="$S/$1"
  mkdir -p "$h/dev" "$h/.claude/projects"
  git clone -q "$S/remote.git" "$h/dev/claude-config"
  printf '[user]\n\temail = t@t\n\tname = t\n' > "$h/.gitconfig"
}
mk_machine A; mk_machine B

sync()  { HOME="$S/$1" "$S/$1/dev/claude-config/bin/sync.sh" "$2" 2>&1; }
# Keys derive from the machine's workspace root, exactly as Claude Code derives
# them: every non-alphanumeric character becomes "-". The fake homes are under
# TMPDIR, so these are not "-Users-you-dev-*" — which is the point: the scripts
# must not assume any particular root.
pfx()   { printf '%s' "$S/$1/dev" | sed 's/[^A-Za-z0-9]/-/g'; }
memdir(){ echo "$S/$1/.claude/projects/$(pfx "$1")${2:+-$2}/memory"; }
write() { # write <machine> <project|""> <file> <content>
  local d; d="$(memdir "$1" "$2")"; mkdir -p "$d"; printf '%s\n' "$4" > "$d/$3"
}
log()   { git -C "$S/$1/dev/claude-config" log --format='%s' ${2:+"$2"} 2>/dev/null; }

echo "== 1. machine A: new project memory + workspace memory, session end"
write A audiodev note.md "from A"
write A ""        MEMORY.md "workspace from A"
out="$(sync A push)"
check "adopted both dirs"        '[ -f "$S/A/dev/claude-config/memory/audiodev/note.md" ] && [ -f "$S/A/dev/claude-config/memory/_workspace/MEMORY.md" ]'
check "symlinked back"           '[ -L "$(memdir A audiodev)" ] && [ -L "$(memdir A "")" ]'
check "pushed to remote"         '[ -z "$(git -C "$S/A/dev/claude-config" rev-list origin/main..HEAD)" ]'
check "commit says memory"       'log A | head -1 | grep -q "^memory: sync"'

echo "== 2. machine B: install.sh links what A created"
HOME="$S/B" "$S/B/dev/claude-config/bin/sync.sh" pull >/dev/null 2>&1
HOME="$S/B" "$S/B/dev/claude-config/bin/install.sh" >/dev/null 2>&1
check "B linked project memory"  '[ -L "$(memdir B audiodev)" ]'
check "B linked workspace key"   '[ -L "$(memdir B "")" ]'
check "B sees A content"         'grep -q "from A" "$(memdir B audiodev)/note.md"'

echo "== 3. config edits get their own commit, not a memory one"
printf 'edited by A\n' > "$S/A/dev/claude-config/CLAUDE.md"
write A audiodev note2.md "more from A"
sync A push >/dev/null
check "two separate commits"     '[ "$(log A | head -2 | grep -c "^\(memory\|config\): sync")" = 2 ]'
check "config commit exists"     'log A | head -2 | grep -q "^config: sync"'
check "memory commit exists"     'log A | head -2 | grep -q "^memory: sync"'

echo "== 4. non-fast-forward: B ran long while A pushed"
write B audiodev from-b.md "from B"          # B has local work, stale checkout
out="$(sync B push)"
check "B push recovered"         '[ -z "$(git -C "$S/B/dev/claude-config" rev-list origin/main..HEAD)" ]'
check "B kept its own work"      'grep -q "from B" "$S/B/dev/claude-config/memory/audiodev/from-b.md"'
check "B picked up A work"       '[ -f "$S/B/dev/claude-config/memory/audiodev/note2.md" ]'
check "no status marker left"    '[ ! -f "$S/B/dev/claude-config/.git/claude-sync-status" ]'

echo "== 5. crash: SessionEnd never ran, next SessionStart captures"
write A audiodev crashed.md "written before a crash"
out="$(sync A pull)"                          # session start, not end
check "captured at session start" 'git -C "$S/A/dev/claude-config" log --format=%s -1 | grep -q "^memory: sync"'
check "and pushed"                '[ -z "$(git -C "$S/A/dev/claude-config" rev-list origin/main..HEAD)" ]'

echo "== 6. real conflict: same file edited on both machines"
sync B pull >/dev/null
printf 'A version\n' > "$S/A/dev/claude-config/memory/audiodev/note.md"
printf 'B version\n' > "$S/B/dev/claude-config/memory/audiodev/note.md"
sync A push >/dev/null
out="$(sync B push 2>&1)"
check "B exits 0 on conflict"    '[ $? = 0 ]'
check "B tree not mid-rebase"    '[ ! -d "$S/B/dev/claude-config/.git/rebase-merge" ] && [ ! -d "$S/B/dev/claude-config/.git/rebase-apply" ]'
check "B keeps its version"      'grep -q "B version" "$S/B/dev/claude-config/memory/audiodev/note.md"'
check "marker written"           '[ -s "$S/B/dev/claude-config/.git/claude-sync-status" ]'
out="$(sync B pull 2>&1)"
check "next start reports it"    'echo "$out" | grep -q "claude-config:"'

echo "== 7. half-finished merge is not committed"
rm -f "$S/B/dev/claude-config/.git/claude-sync-status"
git -C "$S/B/dev/claude-config" rebase --abort 2>/dev/null
before="$(log B | head -1)"
: > "$S/B/dev/claude-config/.git/MERGE_HEAD"
printf 'dirty\n' > "$S/B/dev/claude-config/memory/audiodev/dirty.md"
out="$(sync B push 2>&1)"; rc=$?
rm -f "$S/B/dev/claude-config/.git/MERGE_HEAD"
check "guard exits 0"            '[ "$rc" = 0 ]'
check "nothing committed"        '[ "$(log B | head -1)" = "$before" ]'
check "guard explains itself"    'echo "$out" | grep -qi "merge or rebase in progress"'
check "file left alone"          '[ -f "$S/B/dev/claude-config/memory/audiodev/dirty.md" ]'

echo "== 8. concurrent sessions: second sync is a no-op"
mkdir -p "$S/B/dev/claude-config/.git/claude-sync.lock"
before="$(log B | head -1)"
printf 'racing\n' > "$S/B/dev/claude-config/memory/audiodev/race.md"
out="$(sync B push 2>&1)"; rc=$?
check "locked run exits 0"       '[ "$rc" = 0 ]'
check "locked run committed nothing" '[ "$(log B | head -1)" = "$before" ]'
rmdir "$S/B/dev/claude-config/.git/claude-sync.lock"
sync B push >/dev/null 2>&1
check "unlocked run commits it"  'git -C "$S/B/dev/claude-config" log --format=%s -1 | grep -q "sync from"'
check "lock released"            '[ ! -d "$S/B/dev/claude-config/.git/claude-sync.lock" ]'

echo "== 9. converged: nothing to push, no network round-trip, marker cleared"
# A fresh clone, because B is deliberately left diverged by scenario 6 — it has
# local commits, so it is *correct* for B to attempt a push.
mk_machine C
before="$(git -C "$S/C/dev/claude-config" rev-parse HEAD)"
printf 'claude-config: stale failure from an earlier session\n' \
  > "$S/C/dev/claude-config/.git/claude-sync-status"
# Point the remote at nothing that exists: a push attempt would fail and write a
# marker, so a clean run proves it never reached the network.
git -C "$S/C/dev/claude-config" remote set-url origin "$S/gone.git"
out="$(sync C push 2>&1)"; rc=$?
check "converged push exits 0"   '[ "$rc" = 0 ]'
check "never reached the network" '[ ! -s "$S/C/dev/claude-config/.git/claude-sync-status" ]'
check "stale marker cleared"     '[ ! -f "$S/C/dev/claude-config/.git/claude-sync-status" ]'
check "HEAD unchanged"           '[ "$(git -C "$S/C/dev/claude-config" rev-parse HEAD)" = "$before" ]'
git -C "$S/C/dev/claude-config" remote set-url origin "$S/remote.git"

echo "== 10. link pass: memory from the other machine is linked before anything writes"
# Machine A creates a project. C has pulled it but has never run install.sh, so
# nothing here points at it — the case that used to end in a CONFLICT once the
# first session in that project wrote memory. Uses C, because B is deliberately
# left diverged by scenario 6 and cannot receive anything.
write A jvdev fromA.md "created on A"
sync A push >/dev/null 2>&1
out="$(sync C pull 2>&1)"
check "linked automatically"      '[ -L "$(memdir C jvdev)" ]'
check "reads A content"           'grep -q "created on A" "$(memdir C jvdev)/fromA.md"'
check "link reported"             'echo "$out" | grep -qE "linked [1-9][0-9]* project memory dir"'
check "no conflict was needed"    '! echo "$out" | grep -q CONFLICT'
check "workspace key linked too"  '[ -L "$(memdir C "")" ]'

# What link_pass must NOT do: adopt a populated real directory. Linking there
# would hide content that exists only on this machine, so it belongs to the
# conflict path instead. Exercised through the `link` verb to isolate it.
write A chimedev fromA.md "also on A"
sync A push >/dev/null 2>&1
sync C pull >/dev/null 2>&1
real="$(memdir C chimedev)"
rm -f "$real"                                    # simulate: never linked here
mkdir -p "$real"; printf 'only on C\n' > "$real/local.md"
out="$(sync C link 2>&1)"
check "populated real dir untouched" '[ ! -L "$real" ] && [ -d "$real" ]'
check "local-only content intact"    'grep -q "only on C" "$real/local.md"'
check "nothing claimed to be linked" '! echo "$out" | grep -q "linked"'

# Idempotent: an existing symlink is never disturbed.
before="$(readlink "$(memdir C jvdev)")"
sync C link >/dev/null 2>&1
check "existing symlink unchanged"   '[ "$(readlink "$(memdir C jvdev)")" = "$before" ]'

echo "== 11. no remote configured is still valid"
git -C "$S/A/dev/claude-config" remote remove origin
write A audiodev offline.md "no remote here"
out="$(sync A push 2>&1)"; rc=$?
check "exits 0 without remote"   '[ "$rc" = 0 ]'
check "still commits locally"    'git -C "$S/A/dev/claude-config" log --format=%s -1 | grep -q "sync from"'

echo "== 12. bootstrap: a machine without the workspace tooling pulls it once"
# Machine B's ~/dev is a git repo with a remote, as on a real second machine.
git init --bare -q -b main "$S/wsremote.git"
git -C "$S/B/dev" init -q -b main
printf '/*\n!/.gitignore\n!/tools/\n/tools/*\n!/tools/*.sh\n' > "$S/B/dev/.gitignore"
git -C "$S/B/dev" -c user.email=t@t -c user.name=t add -A
git -C "$S/B/dev" -c user.email=t@t -c user.name=t commit -qm "workspace"
git -C "$S/B/dev" remote add origin "$S/wsremote.git"
git -C "$S/B/dev" push -q -u origin main

# The other machine adds the tooling and pushes it.
git clone -q "$S/wsremote.git" "$S/wsother"
mkdir -p "$S/wsother/tools"
printf '#!/bin/sh\necho tooling\n' > "$S/wsother/tools/workspace-status.sh"
git -C "$S/wsother" -c user.email=t@t -c user.name=t add -A
git -C "$S/wsother" -c user.email=t@t -c user.name=t commit -qm "add tooling"
git -C "$S/wsother" push -q

check "tooling absent to begin with" '[ ! -e "$S/B/dev/tools/workspace-status.sh" ]'
out="$(sync B pull 2>&1)"
check "bootstrap installed it"        '[ -e "$S/B/dev/tools/workspace-status.sh" ]'
check "and said so once"             'echo "$out" | grep -q "install the workspace tooling"'

# Now that it exists, sync.sh must never touch ~/dev again — workspace-status.sh
# owns it from here.
printf 'later\n' > "$S/wsother/tools/another.sh"
git -C "$S/wsother" -c user.email=t@t -c user.name=t add -A
git -C "$S/wsother" -c user.email=t@t -c user.name=t commit -qm "a later change"
git -C "$S/wsother" push -q
out="$(sync B pull 2>&1)"
check "does not pull again"           '[ ! -e "$S/B/dev/tools/another.sh" ]'
check "stays quiet about it"          '! echo "$out" | grep -q "workspace tooling"'

# A dirty workspace tree is never touched, even in the bootstrap case.
rm -rf "$S/B/dev/tools"
rm -f "$S/B/dev/claude-config/.git/workspace-bootstrapped"
printf 'uncommitted\n' >> "$S/B/dev/.gitignore"
out="$(sync B pull 2>&1)"
check "dirty tree blocks bootstrap"  '[ ! -e "$S/B/dev/tools/workspace-status.sh" ]'
check "local edit untouched"         'grep -q uncommitted "$S/B/dev/.gitignore"'

# The guard is a FILENAME. If the tool is renamed upstream, "already installed" can
# never be true on a machine that fetches the new name — so without a one-shot
# marker this would pull ~/dev on every session start forever, silently, because
# the confirmation message keys off the same missing name.
#
# A fresh machine is used because the check requires a CLEAN tree, and deleting
# tracked files to simulate absence would itself be a dirty tree.
git clone -q "$S/wsremote.git" "$S/wsrename"
git -C "$S/wsrename" mv tools/workspace-status.sh tools/renamed-tool.sh
git -C "$S/wsrename" -c user.email=t@t -c user.name=t commit -qm "rename the tool"
git -C "$S/wsrename" push -q

mkdir -p "$S/D"
printf '[user]\n\temail = t@t\n\tname = t\n' > "$S/D/.gitconfig"
git clone -q "$S/remote.git" "$S/D/dev/claude-config"
git clone -q "$S/wsremote.git" "$S/D/dev"  2>/dev/null || {
  # ~/dev already contains claude-config, so clone into place the way a real
  # machine does: init, fetch, hard-reset to the remote's tree.
  git -C "$S/D/dev" init -q -b main
  git -C "$S/D/dev" remote add origin "$S/wsremote.git"
  git -C "$S/D/dev" fetch -q origin main
  git -C "$S/D/dev" -c advice.detachedHead=false checkout -q -B main origin/main
}
check "fresh machine lacks the name"  '[ ! -e "$S/D/dev/tools/workspace-status.sh" ]'
check "and has the renamed one"       '[ -e "$S/D/dev/tools/renamed-tool.sh" ]'
check "its tree is clean"             '[ -z "$(git -C "$S/D/dev" status --porcelain)" ]'

out="$(sync D pull 2>&1)"
check "bootstrap ran once"            '[ -f "$S/D/dev/claude-config/.git/workspace-bootstrapped" ]'
check "reports the missing tool"      'echo "$out" | grep -q "has the workspace tooling moved"'

# Advance ~/dev again. A second session must NOT pull it, even though the expected
# filename is still absent — that is what the marker buys.
printf 'later still\n' > "$S/wsrename/another-file.txt"
git -C "$S/wsrename" -c user.email=t@t -c user.name=t add -A
git -C "$S/wsrename" -c user.email=t@t -c user.name=t commit -qm "more work"
git -C "$S/wsrename" push -q
out="$(sync D pull 2>&1)"
check "does not pull forever"         '[ ! -e "$S/D/dev/another-file.txt" ]'
check "and stays quiet about it"      '! echo "$out" | grep -q "workspace tooling moved"'

echo "== 13. path mapping: a machine whose workspace is not at ~/dev"
# C keeps its own workspace elsewhere. Memory names stay canonical, so both
# machines still agree on memory/<name> — only the local key differs.
mkdir -p "$S/C/elsewhere/projects"
printf '%s\t%s\n' "$(scutil --get ComputerName 2>/dev/null || hostname -s)" \
  "$S/C/elsewhere/projects" > "$S/C/dev/claude-config/path-map.tsv"
mapped_key="$(printf '%s' "$S/C/elsewhere/projects" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$S/C/.claude/projects/$mapped_key-mappedproj/memory"
printf 'written under a different root\n' \
  > "$S/C/.claude/projects/$mapped_key-mappedproj/memory/note.md"
out="$(sync C push 2>&1)"
check "adopted under the mapped root"  '[ -f "$S/C/dev/claude-config/memory/mappedproj/note.md" ]'
check "canonical name, not the path"   '[ ! -d "$S/C/dev/claude-config/memory/$mapped_key-mappedproj" ]'
check "symlinked back to the key"      '[ -L "$S/C/.claude/projects/$mapped_key-mappedproj/memory" ]'

# And the link pass uses the same mapping in reverse.
mkdir -p "$S/C/dev/claude-config/memory/fromother"
printf 'x\n' > "$S/C/dev/claude-config/memory/fromother/note.md"
sync C link >/dev/null 2>&1
check "link pass honours the mapping"  '[ -L "$S/C/.claude/projects/$mapped_key-fromother/memory" ]'
check "did not use the default root"   '[ ! -e "$S/C/.claude/projects/$(pfx C)-fromother/memory" ]'

# A key under the OLD default root is now correctly treated as foreign.
mkdir -p "$S/C/.claude/projects/-Users-$U-dev-strayproj/memory"
printf 'y\n' > "$S/C/.claude/projects/-Users-$U-dev-strayproj/memory/note.md"
out="$(HOME="$S/C" "$S/C/dev/claude-config/bin/adopt-memory.sh" --dry-run 2>&1)"
check "foreign key is skipped"         'echo "$out" | grep -q "skip (not under"'
check "and not adopted"                '[ ! -d "$S/C/dev/claude-config/memory/strayproj" ]'
# A row whose directory does not exist on this machine must be ignored, or one
# machine's custom root — which syncs — would become every machine's.
printf '*\t%s\n' "$S/nowhere/at/all" > "$S/C/dev/claude-config/path-map.tsv"
mkdir -p "$S/C/.claude/projects/$(pfx C)-guardproj/memory"
printf 'z\n' > "$S/C/.claude/projects/$(pfx C)-guardproj/memory/note.md"
out="$(sync C push 2>&1)"
check "ignores a root that is absent"  '[ -f "$S/C/dev/claude-config/memory/guardproj/note.md" ]'
check "fell back to the default root"  '[ -L "$S/C/.claude/projects/$(pfx C)-guardproj/memory" ]'
rm -f "$S/C/dev/claude-config/path-map.tsv"

echo "== 15. a detached settings.json is reported, never moved"
rm -f "$S/A/.claude/settings.json"
printf '{"detached":true}\n' > "$S/A/.claude/settings.json"
out="$(sync A pull 2>&1)"
check "reports the detachment"         'echo "$out" | grep -q "no longer symlinked"'
check "names install.sh as the fix"    'echo "$out" | grep -q "install.sh"'
check "leaves the file alone"          'grep -q detached "$S/A/.claude/settings.json"'

echo "== 16. churn is data, not configuration"
# history.jsonl changes on every prompt. If it landed in the config commit, that
# commit would fire every session and stop meaning "somebody changed the hooks".
mkdir -p "$S/A/dev/claude-config/tasks/sess-1"
printf '{"subject":"a task"}\n' > "$S/A/dev/claude-config/tasks/sess-1/1.json"
sync A push >/dev/null 2>&1
check "tasks are a memory commit"         'log A | head -1 | grep -q "^memory: sync"'
check "no config commit for churn"        '[ "$(log A | head -1 | grep -c "^config: sync")" = "0" ]'
check "the file is actually committed"    'git -C "$S/A/dev/claude-config" show --stat --format= HEAD | grep -q tasks/'

# A real config edit still gets its own commit.
printf 'edited\n' > "$S/A/dev/claude-config/CLAUDE.md"
printf '{"subject":"another task"}\n' > "$S/A/dev/claude-config/tasks/sess-1/2.json"
sync A push >/dev/null 2>&1
check "config edit still separated"       '[ "$(log A | head -2 | grep -c "^\(memory\|config\): sync")" = 2 ]'
check "CLAUDE.md is in the config commit" 'git -C "$S/A/dev/claude-config" show --stat --format= HEAD | grep -q CLAUDE.md'
check "tasks went with memory"            'git -C "$S/A/dev/claude-config" show --stat --format= HEAD~1 | grep -q tasks/'

echo "== 17. session digests: a durable record of what a session did"
# A synthetic transcript in the shape Claude Code writes.
tdir="$S/A/.claude/projects/x"; mkdir -p "$tdir"
cat > "$tdir/sess.jsonl" <<'TRANSCRIPT'
{"timestamp":"2026-07-29T10:00:00.000Z","message":{"role":"user","content":"fix the ADC settle time bug"}}
{"timestamp":"2026-07-29T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"tool_use","input":{"file_path":"/tmp/adc.c"}}]}}
{"timestamp":"2026-07-29T10:01:00.000Z","message":{"role":"user","content":[{"type":"text","text":"now add a test for it"}]}}
{"timestamp":"2026-07-29T10:02:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","input":{"file_path":"/tmp/adc.c"}}]}}
{"timestamp":"2026-07-29T10:30:00.000Z","message":{"role":"user","content":"commit that"}}
{"not":"a shape we know"}
TRANSCRIPT
out="$(HOME="$S/A" "$S/A/dev/claude-config/bin/digest.sh" "$tdir/sess.jsonl" "abcd1234-ffff" "$S/A/dev/myproj" 2>&1)"
dig="$S/A/dev/claude-config/digests/myproj/2026-07-29-abcd1234.md"
check "wrote a digest"               '[ -f "$dig" ]'
check "recorded the first prompt"    'grep -q "fix the ADC settle time bug" "$dig"'
check "listed every prompt"          'grep -q "now add a test for it" "$dig"'
check "counted them"                 'grep -q "^prompts: 3" "$dig"'
check "recorded the machine"         'grep -q "^machine: " "$dig"'
check "recorded elapsed minutes"     'grep -q "^minutes: 30" "$dig"'
check "listed files touched"         'grep -q "adc.c" "$dig"'
check "counted repeat touches"       'grep -q "adc.c.*2×" "$dig"'
check "survived an unknown line"     '! grep -q "a shape we know" "$dig"'
check "says it is mechanical"        'grep -q "not written by Claude" "$dig"'

# A trivial session is not worth a file.
printf '{"timestamp":"2026-07-29T11:00:00.000Z","message":{"role":"user","content":"ls"}}\n' > "$tdir/tiny.jsonl"
out="$(HOME="$S/A" "$S/A/dev/claude-config/bin/digest.sh" "$tdir/tiny.jsonl" "tiny1234" "$S/A/dev/myproj" 2>&1)"; rc=$?
check "skips a trivial session"      '[ ! -f "$S/A/dev/claude-config/digests/myproj/2026-07-29-tiny1234.md" ]'
check "and exits 0 anyway"           '[ "$rc" = 0 ]'

# Garbage and missing input must not break a session ending.
out="$(HOME="$S/A" "$S/A/dev/claude-config/bin/digest.sh" /nonexistent/x.jsonl id cwd 2>&1)"; rc=$?
check "missing transcript exits 0"   '[ "$rc" = 0 ]'
printf 'not json at all\n' > "$tdir/junk.jsonl"
out="$(HOME="$S/A" "$S/A/dev/claude-config/bin/digest.sh" "$tdir/junk.jsonl" id2 "$S/A/dev/myproj" 2>&1)"; rc=$?
check "unparseable transcript exits 0" '[ "$rc" = 0 ]'

# Digests are data: they belong in the memory commit, not the config one.
sync A push >/dev/null 2>&1
check "digest committed as memory"   'log A | head -1 | grep -q "^memory: sync"'
check "the file is in that commit"   'git -C "$S/A/dev/claude-config" show --stat --format= HEAD | grep -q digests/'

echo "== 18. history.jsonl migration: a dangling symlink is repaired, not left"
# A machine that synced history.jsonl before now has a link to a deleted file.
hrepo="$S/A/dev/claude-config/history.jsonl"
printf '{"display":"typed on this machine","timestamp":1}\n' > "$hrepo"
git -C "$S/A/dev/claude-config" add -f history.jsonl >/dev/null 2>&1   # -f: now ignored
git -C "$S/A/dev/claude-config" -c user.email=t@t -c user.name=t commit -qm "add history" >/dev/null 2>&1
git -C "$S/A/dev/claude-config" rm -q history.jsonl >/dev/null 2>&1
git -C "$S/A/dev/claude-config" -c user.email=t@t -c user.name=t commit -qm "stop syncing history" >/dev/null 2>&1
rm -f "$S/A/.claude/history.jsonl"
ln -s "$hrepo" "$S/A/.claude/history.jsonl"
check "symlink is dangling"           '[ -L "$S/A/.claude/history.jsonl" ] && [ ! -e "$S/A/.claude/history.jsonl" ]'
out="$(sync A pull 2>&1)"
check "now a real local file"         '[ -f "$S/A/.claude/history.jsonl" ] && [ ! -L "$S/A/.claude/history.jsonl" ]'
check "content rescued from git"      'grep -q "typed on this machine" "$S/A/.claude/history.jsonl"'
check "said what it did"              'echo "$out" | grep -q "machine-local again"'
check "not re-added to the repo"      '[ ! -e "$hrepo" ]'

# The nastier ordering: Claude Code appended through the dangling link before the
# repair ran, which RE-CREATES the file inside the repo. Those lines are real
# history and must be kept, not thrown away with the stray file.
git -C "$S/A/dev/claude-config" checkout -- . 2>/dev/null
rm -f "$S/A/.claude/history.jsonl"
printf '{"display":"typed through the dangling link","timestamp":2}\n' > "$hrepo"
ln -s "$hrepo" "$S/A/.claude/history.jsonl"
out="$(sync A pull 2>&1)"
check "target existed, still migrated" '[ -f "$S/A/.claude/history.jsonl" ] && [ ! -L "$S/A/.claude/history.jsonl" ]'
check "kept what was written through it" 'grep -q "typed through the dangling link" "$S/A/.claude/history.jsonl"'
check "kept the older rescued lines"   'grep -q "typed on this machine" "$S/A/.claude/history.jsonl"'
check "no duplicate lines"             '[ "$(sort "$S/A/.claude/history.jsonl" | uniq -d | wc -l | tr -d " ")" = "0" ]'
check "repo copy removed again"        '[ ! -e "$hrepo" ]'
check "and gitignored anyway"          'git -C "$S/A/dev/claude-config" check-ignore -q history.jsonl'

echo "== 19. a brand-new user: no ~/.claude at all"
# Not a second machine — a first one. Nothing has ever run here.
fresh="$S/fresh"
mkdir -p "$fresh"
printf '[user]\n\temail = t@t\n\tname = t\n' > "$fresh/.gitconfig"
git clone -q "$S/remote.git" "$fresh/dev/claude-config"
rm -rf "$fresh/dev/claude-config/memory" "$fresh/dev/claude-config/skills" \
       "$fresh/dev/claude-config/tasks" "$fresh/dev/claude-config/history.jsonl"
check "no ~/.claude to begin with"   '[ ! -d "$fresh/.claude" ]'

out="$(HOME="$fresh" "$fresh/dev/claude-config/bin/install.sh" 2>&1)"; rc=$?
check "install.sh exits 0"           '[ "$rc" = 0 ]'
check "created ~/.claude"            '[ -d "$fresh/.claude" ]'
check "linked CLAUDE.md"             '[ -L "$fresh/.claude/CLAUDE.md" ]'
check "created and linked skills"    '[ -L "$fresh/.claude/skills" ] && [ -d "$fresh/dev/claude-config/skills" ]'
check "created and linked tasks"     '[ -L "$fresh/.claude/tasks" ] && [ -d "$fresh/dev/claude-config/tasks" ]'
check "no dangling symlinks"         '! find "$fresh/.claude" -maxdepth 1 -type l ! -exec test -e {} \; -print | grep -q .'
check "no history link yet"          '[ ! -e "$fresh/.claude/history.jsonl" ]'

# Then Claude Code runs for the first time and writes its own history and memory.
printf '{"display":"my very first prompt","timestamp":1}\n' > "$fresh/.claude/history.jsonl"
mkdir -p "$fresh/.claude/projects/$(printf '%s' "$fresh/dev" | sed 's/[^A-Za-z0-9]/-/g')-firstproj/memory"
printf 'learned something\n' \
  > "$fresh/.claude/projects/$(printf '%s' "$fresh/dev" | sed 's/[^A-Za-z0-9]/-/g')-firstproj/memory/note.md"

out="$(HOME="$fresh" "$fresh/dev/claude-config/bin/sync.sh" pull 2>&1)"; rc=$?
check "sync exits 0 on a fresh box"  '[ "$rc" = 0 ]'
check "prompt history stays local"   '[ -f "$fresh/.claude/history.jsonl" ] && [ ! -L "$fresh/.claude/history.jsonl" ]'
check "and is never committed"        '[ ! -e "$fresh/dev/claude-config/history.jsonl" ]'
check "adopted the first memory"     '[ -f "$fresh/dev/claude-config/memory/firstproj/note.md" ]'
check "committed it"                 'git -C "$fresh/dev/claude-config" log --format=%s -1 | grep -q "sync from"'

echo "== 20. a marker is not believed past the thing it described"
# A transient fetch failure writes the same marker a real conflict does. The
# difference is only visible afterwards: a conflict leaves local work stranded, a
# dropped network leaves nothing behind. Reporting both forever trains the reader
# to ignore the line that matters.
#
# Section 11 removed A's remote on purpose and never put it back, so re-attach it
# here rather than depending on an earlier section's leftovers.
# `remote remove` also drops branch.main.remote, so the upstream has to be put
# back before converging — push_now returns early on a branch that has none.
git -C "$S/A/dev/claude-config" remote add origin "$S/remote.git" 2>/dev/null
git -C "$S/A/dev/claude-config" fetch -q origin
git -C "$S/A/dev/claude-config" branch --set-upstream-to=origin/main main >/dev/null 2>&1
sync A pull >/dev/null; sync A push >/dev/null           # converge A

marker() { # marker <machine> <verifiable|sticky> <text>
  printf 'claude-config: %s [2026-01-01 09:00]\n' "$3" > "$S/$1/dev/claude-config/.git/claude-sync-status"
  if [ "$2" = verifiable ]; then : > "$S/$1/dev/claude-config/.git/claude-sync-status-verifiable"
  else rm -f "$S/$1/dev/claude-config/.git/claude-sync-status-verifiable"; fi
}

marker A verifiable "pull failed — keeping local copy"
out="$(sync A status)"
check "cured marker not reported"     '! echo "$out" | grep -q "pull failed"'
check "and cleared, not left to rot"  '[ ! -f "$S/A/dev/claude-config/.git/claude-sync-status" ]'

# The same marker, with local work actually stranded, must survive.
write A audiodev stranded.md "not on the remote"
git -C "$S/A/dev/claude-config" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$S/A/dev/claude-config" -c user.email=t@t -c user.name=t commit -qm "memory: stranded" >/dev/null
marker A verifiable "push failed — 1 local commit(s) not on the remote yet"
out="$(sync A status)"
check "live marker still reported"    'echo "$out" | grep -q "push failed"'

# A marker nothing local can disprove is sticky, converged or not.
sync A push >/dev/null
marker A sticky "expected tools/workspace-status.sh in ~/dev — has the workspace tooling moved?"
out="$(sync A status)"
check "sticky marker survives"        'echo "$out" | grep -q "workspace tooling moved"'
check "markers carry a timestamp"     'echo "$out" | grep -qE "\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\]"'
rm -f "$S/A/dev/claude-config/.git/claude-sync-status"

echo "== 21. a failed pull does not swallow the push"
# The failure that actually loses a handoff is local commits that never leave the
# machine. A dead fetch says nothing about whether the push would work, so it
# must not skip it — the old `rebase_onto_remote && push_now` did exactly that.
#
# Unreachable origin makes BOTH fail, which is the point: what is asserted is
# that push_now still RAN. Only push_now writes "push failed", so the marker text
# is the evidence. Under the short-circuit it stayed "pull failed" forever.
sync A pull >/dev/null; sync A push >/dev/null
write A audiodev after-a-dead-fetch.md "must be attempted"
git -C "$S/A/dev/claude-config" remote set-url origin "$S/nowhere.git"
out="$(sync A pull 2>&1)"; rc=$?
check "pull verb still exits 0"   '[ "$rc" = 0 ]'
check "the push was attempted"    '[ -s "$S/A/dev/claude-config/.git/claude-sync-status" ] && grep -q "push failed" "$S/A/dev/claude-config/.git/claude-sync-status"'
check "and the work is committed" 'git -C "$S/A/dev/claude-config" log --format=%s -1 | grep -q "sync from"'

# With the remote reachable again the same path converges and clears itself.
git -C "$S/A/dev/claude-config" remote set-url origin "$S/remote.git"
out="$(sync A pull 2>&1)"
check "recovers on the next start" '[ -z "$(git -C "$S/A/dev/claude-config" rev-list origin/main..HEAD)" ]'
check "marker gone once converged" '[ ! -f "$S/A/dev/claude-config/.git/claude-sync-status" ]'
check "and the work reached B"     'git -C "$S/B/dev/claude-config" fetch -q origin && git -C "$S/B/dev/claude-config" cat-file -e origin/main:memory/audiodev/after-a-dead-fetch.md'

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
