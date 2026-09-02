# templates

The scripts, ready to copy. All use `$HOME` and `id -un`, so they work under any
username without editing.

| Script | Goes to | Does |
|---|---|---|
| `install.sh` | `~/dev/claude-config/bin/` | Links config, memory, tasks and prompt history into `~/.claude` |
| `sync.sh` | `~/dev/claude-config/bin/` | Syncs all of that from the session hooks |
| `adopt-memory.sh` | `~/dev/claude-config/bin/` | Absorbs memory for newly created projects |
| `digest.sh` | `~/dev/claude-config/bin/` | Writes a short record of each session at SessionEnd |
| `lib-paths.sh` | `~/dev/claude-config/bin/` | The one place a project path becomes a memory key |
| `path-map.tsv` | `~/dev/claude-config/` | Where the workspace lives on each machine |
| `sync-test.sh` | `~/dev/claude-config/test/` | 116 assertions across two simulated machines |
| `bootstrap.sh` | `~/dev/` | Clones every project in `repos.tsv` (never pulls) |
| `new-project.sh` | `~/dev/tools/` | Starts a project properly in one command |
| `workspace-status.sh` | `~/dev/tools/` | Reports what is out of sync; silent when clean |
| `catch-up.sh` | `~/dev/tools/` | Acts on that report — clone, fast-forward, link memory |
| `asset-inventory.sh` | `~/dev/tools/` | Indexes the big files that never sync |
| `workspace-test.sh` | `~/dev/test/` | 72 assertions across a simulated workspace |

Run both test scripts before you rely on any of this. They build fake machines and
a fake GitHub, then play out the ways syncing goes wrong.

```sh
chmod +x <script>
```

## Nothing needs editing

There is deliberately no username, GitHub account, or absolute path hardcoded in
any of them. Personalisation lives in **data**, not code:

- `~/dev/repos.tsv` — your projects and their URLs
- `~/dev/claude-config/CLAUDE.md` — your conventions
- `git config --global user.name` / `user.email` — your identity

## A note on `sync.sh` and `adopt-memory.sh`

Both run from session hooks and are written to **never fail and never hang** —
every path exits 0, and git gets a short network timeout. A hook that breaks
session startup is far worse than memory syncing one session late.

`adopt-memory.sh` refuses to merge. If the same project has memory in both the
repo and as a real directory (usually because another machine got there first),
it leaves both alone and tells you. Merging silently could lose work.

`sync.sh` follows the same instinct — it stops rather than guesses. It refuses to
commit while a merge or rebase is unfinished, holds a lock so two open sessions
cannot sync at once, and aborts a conflicted rebase instead of leaving the repo
mid-operation. A push rejected because another machine pushed first is rebased
and retried once; anything still unresolved is written to
`.git/claude-sync-status` and printed at the next session start, because output
at session *end* is read by nobody.

It commits in two commits — `memory:` for `memory/`, `config:` for everything
else — so history stays legible when the scripts themselves change. And it
captures at session start as well as end, so a session that dies without running
SessionEnd does not strand its memory.

`sync-test.sh` builds a bare repo and two fake homes and plays out all of it:
adoption, the commit split, a stale push, a crashed session, a real conflict, a
half-finished merge, two sessions racing, the link pass, and no remote configured.

## A note on `workspace-status.sh` and `catch-up.sh`

These two split reporting from acting, on purpose. The report runs from the
session hook and is **silent unless something needs attention** — a report that
prints every time becomes wallpaper, and then a real warning goes unread. Its
output goes to stdout because `SessionStart` stdout is added to the agent's
context, so the agent can offer to fix what it finds.

Fetching every repo takes seconds, so it cannot happen at session start: the
report reads local refs and is instant, while a detached `refresh` makes those
refs current for the *next* session. `now` does both when you want a live answer.

`catch-up.sh` only ever fast-forwards, never merges or rebases, and refuses any
repo with uncommitted changes — then tells you what it left alone. The workspace
repo is the single exception it may pull and push by itself, because a project
announces itself through a manifest row; even there it never commits.

`workspace-test.sh` forces every state — missing, behind, dirty, diverged,
current — against local bare remotes.
