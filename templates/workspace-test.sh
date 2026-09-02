#!/usr/bin/env bash
#
# workspace-test.sh — simulation for workspace-status.sh and catch-up.sh.
#
# Stands up a fake ~/dev: a workspace repo with its own bare remote, a manifest,
# and project repos forced into each interesting state — missing, behind, dirty,
# diverged, current. Then checks that the report says the right thing and that
# catch-up.sh acts only where it is safe to.
#
# Run after touching either script. Writes only inside its own scratch dir.
#
#   ./test/workspace-test.sh
#
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${TMPDIR:-/tmp}/workspace-test.$$"
trap 'rm -rf "$S"' EXIT
rm -rf "$S"; mkdir -p "$S"

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
# pipefail is right for this harness's setup code and wrong for assertions: a
# `git log | grep -q` pipeline exits early by design, git dies of SIGPIPE, and
# pipefail then calls a correct assertion a failure — intermittently, depending
# on which process wins. So assertions run with it off.
check(){ set +o pipefail; if eval "$2"; then ok "$1"; else bad "$1"; fi; set -o pipefail; }

G=(git -c user.email=t@t -c user.name=t)

# --- a project repo with a bare remote, cloned into the fake ~/dev ------------
mk_project() { # mk_project <name>
  local n="$1"
  git init --bare -q -b main "$S/remotes/$n.git"
  git clone -q "$S/remotes/$n.git" "$S/build/$n"
  printf 'v1\n' > "$S/build/$n/file.txt"
  "${G[@]}" -C "$S/build/$n" add -A; "${G[@]}" -C "$S/build/$n" commit -qm init
  "${G[@]}" -C "$S/build/$n" push -q origin main
  git clone -q "$S/remotes/$n.git" "$S/dev/$n"
  printf '%s\tmine\t%s\n' "$n" "$S/remotes/$n.git" >> "$S/dev/repos.tsv"
}

# advance the remote so the local clone falls behind
advance() { # advance <name>
  printf 'v2\n' >> "$S/build/$1/file.txt"
  "${G[@]}" -C "$S/build/$1" commit -qam next
  "${G[@]}" -C "$S/build/$1" push -q origin main
}

mkdir -p "$S/remotes" "$S/build" "$S/dev/tools" "$S/dev/test"
cp "$SRC/tools/workspace-status.sh" "$SRC/tools/catch-up.sh" "$S/dev/tools/"
cp "$SRC/bootstrap.sh" "$S/dev/"
chmod +x "$S/dev/tools"/*.sh "$S/dev/bootstrap.sh"

# the workspace repo itself, with a remote, recorded as "." like the real one
git init --bare -q -b main "$S/remotes/workspace.git"
printf '# path\tkind\turl\n' > "$S/dev/repos.tsv"
printf '.\tmine\t%s\n' "$S/remotes/workspace.git" >> "$S/dev/repos.tsv"

mk_project current
mk_project behindone
mk_project dirtyone
mk_project divergedone
# a project in the manifest that was never cloned here
git init --bare -q -b main "$S/remotes/absent.git"
git clone -q "$S/remotes/absent.git" "$S/build/absent"
printf 'x\n' > "$S/build/absent/file.txt"
"${G[@]}" -C "$S/build/absent" add -A; "${G[@]}" -C "$S/build/absent" commit -qm init
"${G[@]}" -C "$S/build/absent" push -q origin main
printf 'absent\tmine\t%s\n' "$S/remotes/absent.git" >> "$S/dev/repos.tsv"

cd "$S/dev"
# Mirror the real ~/dev strategy: ignore everything, whitelist the workspace
# documents. Without this the nested project clones are tracked as gitlinks, the
# workspace tree is permanently dirty, and converge() correctly refuses to act.
cat > "$S/dev/.gitignore" <<'EOF'
/*
!/.gitignore
!/repos.tsv
!/bootstrap.sh
!/tools/
!/test/
!/assets/
/assets/*.txt
EOF
"${G[@]}" init -q -b main
"${G[@]}" add -A >/dev/null 2>&1
"${G[@]}" commit -qm "workspace" >/dev/null 2>&1
"${G[@]}" remote add origin "$S/remotes/workspace.git"
"${G[@]}" push -q -u origin main

# force the states
advance behindone
advance divergedone
advance dirtyone          # behind AND dirty: the case catch-up must refuse
printf 'local edit\n' >> "$S/dev/dirtyone/file.txt"
printf 'local commit\n' >> "$S/dev/divergedone/file.txt"
"${G[@]}" -C "$S/dev/divergedone" commit -qam "local work"

run() { HOME="$S/fakehome" "$S/dev/tools/$1" "${2:-}" "${3:-}" 2>&1; }
mkdir -p "$S/fakehome"

echo "== 1. report before any fetch: local facts only"
out="$(run workspace-status.sh report)"
check "reports the missing project"  'echo "$out" | grep -q "absent"'
check "points at catch-up"           'echo "$out" | grep -q "catch-up.sh"'
check "reports the dirty tree"       'echo "$out" | grep -q "dirtyone"'
check "says no fetch recorded yet"   'echo "$out" | grep -qi "no fetch recorded"'
check "silent about current repo"    '! echo "$out" | grep -q "current ("'

echo "== 2. after a fetch, staleness is known"
run workspace-status.sh refresh >/dev/null
out="$(run workspace-status.sh report)"
check "knows behindone is behind"    'echo "$out" | grep -q "behind origin.*behindone"'
check "counts it"                    'echo "$out" | grep -qE "behindone \([0-9]+\)"'
check "sees diverged local commits"  'echo "$out" | grep -q "unpushed:.*divergedone"'
check "stamp written"                '[ -f "$S/dev/.git/workspace-fetch-stamp" ]'

echo "== 3. converge: clean fast-forward pull of the workspace repo"
other="$S/other"; git clone -q "$S/remotes/workspace.git" "$other"
printf 'newproj\tmine\t-\n' >> "$other/repos.tsv"
"${G[@]}" -C "$other" commit -qam "add newproj row"; "${G[@]}" -C "$other" push -q
out="$(run workspace-status.sh report)"
check "pulled ~/dev"                 'echo "$out" | grep -q "pulled ~/dev"'
check "manifest row arrived"         'grep -q "^newproj" "$S/dev/repos.tsv"'

echo "== 4. converge: pushes only when clean, never commits"
printf 'x\tmine\t-\n' >> "$S/dev/repos.tsv"        # uncommitted manifest edit
out="$(run workspace-status.sh report)"
check "did not commit for me"        '[ -n "$(git -C "$S/dev" status --porcelain)" ]'
check "nothing pushed"               '[ "$(git -C "$S/dev" rev-list --count "@{u}..HEAD")" = "0" ]'
git -C "$S/dev" checkout -- repos.tsv

"${G[@]}" -C "$S/dev" commit -q --allow-empty -m "a commit I made deliberately"
out="$(run workspace-status.sh report)"
check "pushed my own commit"         '[ "$(git -C "$S/dev" rev-list --count "@{u}..HEAD")" = "0" ]'
check "said so"                      'echo "$out" | grep -q "pushed ~/dev"'

echo "== 5. converge: dirty tree blocks the push and warns about the manifest"
printf 'blocked\tmine\t-\n' >> "$S/dev/repos.tsv"
"${G[@]}" -C "$S/dev" commit -qam "add blocked row"
# Dirty a TRACKED file. An untracked file at the root does not count: the
# whitelist .gitignore ignores it, here and in the real ~/dev.
printf '# a note I have not committed\n' >> "$S/dev/repos.tsv"
out="$(run workspace-status.sh report)"
check "reports unpushed + dirty"     'echo "$out" | grep -q "unpushed commit(s) and a dirty tree"'
check "warns about repos.tsv rows"   'echo "$out" | grep -q "cannot see those projects yet"'
check "still did not push"           '[ "$(git -C "$S/dev" rev-list --count "@{u}..HEAD")" != "0" ]'
git -C "$S/dev" checkout -- repos.tsv

echo "== 6. catch-up --dry-run changes nothing"
before="$(git -C "$S/dev/behindone" rev-parse HEAD)"
out="$(run catch-up.sh --dry-run)"
check "dry run says it would pull"   'echo "$out" | grep -q "would pull  behindone"'
check "dry run touched nothing"      '[ "$(git -C "$S/dev/behindone" rev-parse HEAD)" = "$before" ]'
check "absent still missing"         '[ ! -d "$S/dev/absent" ]'

echo "== 7. catch-up acts where safe, refuses where not"
out="$(run catch-up.sh)"
check "cloned the missing project"   '[ -d "$S/dev/absent/.git" ]'
check "pulled the behind project"    '[ "$(git -C "$S/dev/behindone" rev-parse HEAD)" != "$before" ]'
check "skipped the dirty one"        'echo "$out" | grep -q "SKIP  dirtyone"'
check "kept the dirty edit"          'grep -q "local edit" "$S/dev/dirtyone/file.txt"'
check "skipped the diverged one"     'echo "$out" | grep -q "SKIP  divergedone"'
check "kept the local commit"        'git -C "$S/dev/divergedone" log --oneline | grep -q "local work"'
check "explains what it left"        'echo "$out" | grep -q "Left alone on purpose"'
check "nothing merged or rebased"    '[ ! -d "$S/dev/divergedone/.git/rebase-merge" ]'

echo "== 8. report is silent once everything is level"
git -C "$S/dev/dirtyone" checkout -- file.txt
git -C "$S/dev/divergedone" reset -q --hard 'origin/main'
run catch-up.sh >/dev/null
git -C "$S/dev" status --porcelain | grep -q . && git -C "$S/dev" stash -q 2>/dev/null
# The first report still has work to do — scenario 5's dirty tree blocked a push,
# and it goes out now. Silence means STEADY state, so check the second run.
first="$(run workspace-status.sh report)"
check "acted on the blocked push"    'echo "$first" | grep -q "pushed ~/dev"'
out="$(run workspace-status.sh report)"
check "silent when clean"            '[ -z "$(echo "$out" | grep -v "^$")" ]'

echo "== 9. a new top-level folder is spotted, and nothing else is"
mkdir -p "$S/dev/brandnew" "$S/dev/current/src" "$S/dev/reference/somebodyelse" "$S/dev/other/frozen"
out="$(run workspace-status.sh report "$S/dev/brandnew")"
check "spots the untracked folder"   'echo "$out" | grep -q "brandnew/ is not a git repo"'
check "offers the exact command"     'echo "$out" | grep -q "new-project.sh \"brandnew\""'

out="$(run workspace-status.sh report "$S/dev/current/src")"
check "silent inside a tracked repo" '! echo "$out" | grep -q "not a git repo"'
out="$(run workspace-status.sh report "$S/dev")"
check "silent in the workspace root" '! echo "$out" | grep -q "not a git repo"'
out="$(run workspace-status.sh report "$S/dev/reference/somebodyelse")"
check "silent in reference/"         '! echo "$out" | grep -q "not a git repo"'
out="$(run workspace-status.sh report "$S/dev/other/frozen")"
check "silent in other/"             '! echo "$out" | grep -q "not a git repo"'
out="$(run workspace-status.sh report "/tmp")"
check "silent outside ~/dev"         '! echo "$out" | grep -q "not a git repo"'

# A folder already recorded in the manifest is not new, even without a clone yet.
printf 'plannedproj\tmine\t-\n' >> "$S/dev/repos.tsv"
mkdir -p "$S/dev/plannedproj"
out="$(run workspace-status.sh report "$S/dev/plannedproj")"
check "silent when already tracked"  '! echo "$out" | grep -q "not a git repo"'
git -C "$S/dev" checkout -- repos.tsv 2>/dev/null

echo "== 10. the current project is checked synchronously, not from cache"
# Move the remote AFTER the last refresh, so only a fresh fetch can see it.
advance current
out="$(run workspace-status.sh report "$S/dev/current")"
check "spotted without a refresh"    'echo "$out" | grep -q "current is 1 commit(s) behind"'
check "says it is what you are in"   'echo "$out" | grep -q "what you are working in"'
check "offers the pull command"      'echo "$out" | grep -q "pull --ff-only"'
check "not double-listed below"      '[ "$(echo "$out" | grep -c "^workspace: behind origin.*current")" = "0" ]'

# A subdirectory resolves to its enclosing repo.
out="$(run workspace-status.sh report "$S/dev/current/src")"
check "subdir resolves to the repo"  'echo "$out" | grep -q "current is 1 commit(s) behind"'

# Behind AND dirty gets different advice, because a pull there is not a fast-forward.
printf 'edit\n' >> "$S/dev/current/file.txt"
out="$(run workspace-status.sh report "$S/dev/current")"
check "warns instead of offering"    'echo "$out" | grep -q "AND has uncommitted changes"'
check "explains why"                 'echo "$out" | grep -q "not a fast-forward"'
git -C "$S/dev/current" checkout -- file.txt

# Local commits are reported as unpushed.
"${G[@]}" -C "$S/dev/current" commit -q --allow-empty -m "local only"
out="$(run workspace-status.sh report "$S/dev/current")"
check "reports unpushed commits"     'echo "$out" | grep -q "current has 1 commit(s) not pushed"'

# Other repos are still reported from cache in the same run.
out="$(run workspace-status.sh report "$S/dev/current")"
check "others still reported"        'echo "$out" | grep -qE "behind origin|not a git repo|uncommitted"'

echo "== 11. asset inventory: the index travels, the assets stay put"
cp "$SRC/tools/asset-inventory.sh" "$S/dev/tools/"
chmod +x "$S/dev/tools/asset-inventory.sh"
mkdir -p "$S/dev/other" "$S/dev/archive" "$S/dev/other/node_modules"
dd if=/dev/zero of="$S/dev/other/recording.wav" bs=1m count=2 2>/dev/null
dd if=/dev/zero of="$S/dev/other/node_modules/junk.bin" bs=1m count=2 2>/dev/null
printf 'tiny\n' > "$S/dev/archive/notes.txt"
inv() { HOME="$S/fakehome" "$S/dev/tools/asset-inventory.sh" "$@" 2>&1; }

out="$(inv scan)"
me="$(ls "$S/dev/assets"/*.tsv | head -1)"
check "seeded scan-paths.tsv"      '[ -f "$S/dev/assets/scan-paths.tsv" ]'
check "listed the big asset"       'grep -q "other/recording.wav" "$me"'
check "skipped the tiny file"      '! grep -q "archive/notes.txt" "$me"'
check "skipped build/package dirs" '! grep -q node_modules "$me"'
check "recorded a size"            'grep -q "recording.wav	2097152" "$me"'

# The other machine's inventory arrives as a committed text file.
printf '# path\tbytes\tmtime\nother/only-on-theirs.mov\t5242880\t1\nother/recording.wav\t2097152\t1\n' \
  > "$S/dev/assets/thirteen-inch.tsv"
out="$(inv diff)"
check "reports what is missing here" 'echo "$out" | grep -q "only-on-theirs.mov"'
check "sizes it"                     'echo "$out" | grep -qE "NOT here:.*5\.0M"'
check "silent about the shared file"  '[ "$(echo "$out" | grep -c "recording.wav")" = "0" ]'

out="$(inv plan)"
check "wrote a pull list"            '[ -s "$S/dev/assets/pull-from-thirteen-inch.txt" ]'
check "pull list has the right file" 'grep -qx "other/only-on-theirs.mov" "$S/dev/assets/pull-from-thirteen-inch.txt"'
check "offers an rsync command"      'echo "$out" | grep -q "rsync -av --files-from"'
check "names a host to edit"         'echo "$out" | grep -q "thirteen-inch.local"'

# discover: a large ignored asset is proposed; build output is not.
mkdir -p "$S/dev/current/Debug"
printf 'Debug/\n*.bin\n' > "$S/dev/current/.gitignore"
dd if=/dev/zero of="$S/dev/current/big-upload.bin" bs=1m count=11 2>/dev/null
dd if=/dev/zero of="$S/dev/current/Debug/firmware.bin" bs=1m count=11 2>/dev/null
git -C "$S/dev/current" add .gitignore 2>/dev/null
"${G[@]}" -C "$S/dev/current" commit -qm "ignore rules" 2>/dev/null
out="$(inv discover)"
check "proposes the real asset"       'echo "$out" | grep -q "current/big-upload.bin"'
check "ignores build output"          '! echo "$out" | grep -q "Debug/firmware.bin"'

echo "== 12. a gitignored workspace file is reported, not silently lost"
out="$(run workspace-status.sh report)"
check "silent while all visible"     '! echo "$out" | grep -q "will never sync"'

# Simulate the trap: a new tool that no whitelist covers.
printf '/*\n!/.gitignore\n!/repos.tsv\n!/bootstrap.sh\n!/assets/\n/assets/*.txt\n!/tools/\n/tools/*\n!/tools/workspace-status.sh\n!/tools/catch-up.sh\n!/tools/asset-inventory.sh\n' \
  > "$S/dev/.gitignore"
printf '#!/bin/sh\necho new\n' > "$S/dev/tools/brand-new-tool.sh"
out="$(run workspace-status.sh report)"
check "names the invisible file"     'echo "$out" | grep -q "tools/brand-new-tool.sh"'
check "says it will never sync"      'echo "$out" | grep -q "will never sync"'
check "points at the directory fix"  'echo "$out" | grep -q "add the directory, not the file"'

# Whitelisting the directory fixes it, and the report goes quiet again.
printf '/*\n!/.gitignore\n!/repos.tsv\n!/bootstrap.sh\n!/tools/\n!/assets/\n/assets/*.txt\n' > "$S/dev/.gitignore"
out="$(run workspace-status.sh report)"
check "quiet once whitelisted"       '! echo "$out" | grep -q "will never sync"'
check "project trees still ignored"  'git -C "$S/dev" check-ignore -q current/file.txt'

echo "== 13. the cross-repo reference still points at something real"
# claude-config/bin/sync.sh names one path in THIS repo — the tool whose absence
# triggers its one-time bootstrap of ~/dev. That is a hardcoded reference across a
# repo boundary, and nothing but this assertion connects the two. Rename or move the
# tool without updating sync.sh and the bootstrap either never fires (a machine
# silently stays behind) or fires forever. Both are silent; this is not.
syncsh="$SRC/claude-config/bin/sync.sh"
if [ -f "$syncsh" ]; then
  declared="$(sed -n 's/^WORKSPACE_TOOL="\(.*\)"$/\1/p' "$syncsh" | head -1)"
  check "sync.sh declares the path"    '[ -n "$declared" ]'
  check "and it exists in ~/dev"       '[ -n "$declared" ] && [ -e "$SRC/$declared" ]'
  check "the path is tracked by git"   '[ -n "$declared" ] && git -C "$SRC" ls-files --error-unmatch "$declared" >/dev/null 2>&1'
  check "no stray literal references"  '[ "$(grep -c "tools/workspace-status\.sh" "$syncsh")" -le 1 ]'
else
  echo "  SKIP  claude-config not present beside this repo"
fi

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
