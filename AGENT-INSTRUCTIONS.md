# Instructions for a Claude Code agent

You are setting this system up **for a beginner**, on their machine, with their
accounts. They may not know what a commit is. Read this fully before acting.

Their machine may be macOS, Linux, or Windows running WSL2. **Detect which before
running anything** — see Preconditions. The workspace design is identical on all
three; only tool installation differs.

---

## What you are building

A workspace where every project is a private GitHub repo, Claude's per-project
memory syncs between machines, and a new machine can be reproduced from a
manifest. Five pieces:

1. `~/dev/` — the workspace, one predictable home for every project
2. `~/dev/claude-config/` — private repo holding `CLAUDE.md`, settings, skills,
   per-project memory, task lists and session digests, symlinked into `~/.claude`
3. `~/dev/` as a git repo — tracks `repos.tsv` (the manifest), `bootstrap.sh`, and
   the tooling. It keeps *itself* current: fetched, fast-forwarded and pushed when
   clean, never committed on their behalf
4. `~/dev/tools/new-project.sh` — one command to start a project correctly
5. `~/dev/tools/workspace-status.sh` + `catch-up.sh` — a session-start report that
   is **silent unless something needs them**, and one command that acts on it

The scripts already exist in `templates/`. **Copy them; do not rewrite them.**
They are tested, they contain no hardcoded username or path, and they handle
failure modes that are not obvious from reading them.

**The principle behind the design, worth explaining as you go:** everything
automatic is something that cannot lose work — fetching, fast-forwarding,
symlinking, committing Claude's own memory. Everything that could lose work —
merging, rebasing, pushing their code, committing unfinished writing — is reported
and left to them.

---

## How to behave

**Explain as you go, briefly.** One or two sentences per step about what you're
doing and why. They are learning, not just receiving a configured machine.

**Never invent their identity.** Ask for their GitHub username. Derive the
numeric ID with `gh api user --jq '.id'`. Do not guess an email.

**Confirm before anything outward-facing.** Creating a GitHub repo is visible and
hard to fully undo. Ask before each `gh repo create`, and always pass
`--private`.

**Verify each step before moving on.** Check the symlink resolves, the repo
exists, the push succeeded. Report what you checked. Silent failure here produces
a system that looks fine and loses work later.

**Never** `git init` in their home directory, touch `~/Documents` wholesale, or
run destructive commands on folders you have not inspected.

---

## Preconditions

### First, establish where you are

This setup runs on macOS, Linux, or Linux-under-Windows (WSL2). The build order
is identical on all three; only how you install missing tools differs.

```sh
uname -s                        # Darwin = macOS, Linux = Linux or WSL2
grep -qi microsoft /proc/version 2>/dev/null && echo "WSL2"
pwd                             # sanity check on where you are
id -un                          # note it; matters for a second machine later
```

**If you detect WSL2, check this before anything else:**

```sh
echo "$HOME"                    # must be /home/<user>, NOT /mnt/c/...
```

If `$HOME` is under `/mnt/c/`, stop and tell them. A workspace on the Windows
drive works but is severely slow, in a way that is very hard to diagnose months
later. `~/dev` must live on the Linux filesystem.

**If `uname -s` returns something else** — including anything indicating native
Windows, PowerShell or CMD — stop. These scripts are bash and will not run.
Point them at `04-ENVIRONMENT.md` and let them decide between installing WSL2 and
using Claude Code without the workspace tooling. Do not attempt a translation.

### Then check the tools

```sh
git --version
gh --version
gh auth status          # else: gh auth login  (user does this interactively)
```

To install anything missing, use the platform's own package manager — do not
assume Homebrew:

| Platform | Missing `git` | Missing `gh` |
|---|---|---|
| macOS | `xcode-select --install` | `brew install gh` (Homebrew first if absent) |
| WSL2 / Debian / Ubuntu | `sudo apt update && sudo apt install -y git` | `sudo apt install -y gh` |
| Fedora / RHEL | `sudo dnf install git` | `sudo dnf install gh` |
| Arch | `sudo pacman -S git` | `sudo pacman -S github-cli` |

If `apt` reports `gh` is unavailable, their distribution is older than the version
carrying it — send them to
<https://github.com/cli/cli/blob/trunk/docs/install_linux.md> rather than guessing
at a repository configuration.

Anything requiring `sudo` must be run **by them**. You will not have their
password, and you should not ask for it.

`gh auth login` must also be run **by them** — it opens a browser. Ask them to run
it and tell you when it's done. On WSL2 the browser opens on the Windows side;
that is expected. If no browser opens, it prints a code and URL they can use
anywhere.

### If Claude Code itself is missing

You are running, so it exists somewhere — but if they mention a second machine or
a reinstall, the current install method on macOS, Linux and WSL is:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

Self-contained binary, no Node.js, auto-updating. The older
`npm install -g @anthropic-ai/claude-code` still works but is no longer the
recommended path. `claude doctor` diagnoses a broken install without starting a
session.

**Never install Claude Code on both native Windows and WSL2.** They are separate
programs with separate `~/.claude` directories and separate project memory keyed
to incompatible path shapes (`C:\Users\...` versus `/home/...`). The symptom is
memory that silently vanishes. If they have both, have them remove the Windows
one.

---

## Build order

### 1. Git identity

```sh
gh api user --jq '.id'          # e.g. 1234567
```

Then, with their name and username:

```sh
git config --global user.name  "<Their Name>"
git config --global user.email "<id>+<username>@users.noreply.github.com"
```

Explain: the noreply address keeps their real email out of every commit forever,
and GitHub still attributes it because it matches on the numeric ID.

### 2. Global ignore file

Write `~/.gitignore_global` covering **all three platforms**, not just the one
they are on — they may add a different machine later, and one file that works
everywhere is the point:

- macOS: `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`
- Linux: `*~`, `.directory`, `.Trash-*`
- Windows (files can cross over via WSL): `Thumbs.db`, `desktop.ini`
- Editors: `.vscode/`, `.idea/`, `*.swp`
- Claude Code machine-local: `**/.claude/settings.local.json`, `**/.claude/*.lock`

Then:

```sh
git config --global core.excludesfile ~/.gitignore_global
```

The `**/` prefix is required — a pattern containing a slash is anchored to the
repo root and will not match in subfolders.

### 3. Workspace skeleton

```sh
mkdir -p ~/dev/{tools,test,assets} ~/dev/claude-config/{bin,memory,skills,test}
```

### 4. claude-config

- Copy `templates/{install,sync,adopt-memory,lib-paths,digest}.sh` → `~/dev/claude-config/bin/`, `chmod +x`
- Copy `templates/path-map.tsv` → `~/dev/claude-config/` (the `*` row is enough unless a machine's workspace is not at `~/dev`)
- Copy `templates/sync-test.sh` → `~/dev/claude-config/test/`, `chmod +x`
- Write `.gitignore` containing `.DS_Store` and `tasks/**/.lock` — a task lock
  belongs to a running process on one machine
- Do **not** sync `~/.claude/history.jsonl`. Prompt history stays machine-local;
  session digests carry what actually matters, and far more cheaply
- **Run `test/sync-test.sh` and show them the result before going further.** It
  simulates two machines through crashes, races and conflicts. Do not build on a
  failing sync
- Write `CLAUDE.md` with their conventions (see "CLAUDE.md content" below)
- Write `settings.json` with four hooks: `sync.sh pull` and
  `workspace-status.sh report` at SessionStart; `digest.sh` then `sync.sh push` at
  SessionEnd (digest first, so the session's record is included in that commit)
- **If `~/.claude/settings.json` already exists, move it in and merge the hooks
  into the existing object — do not overwrite their settings**
- `git init`, commit, then **ask** before `gh repo create claude-config --private --source=. --push`
- Run `bin/install.sh` and verify with `ls -la ~/.claude/CLAUDE.md`

### 5. Workspace repo

- Write `~/dev/.gitignore` using the **ignore-everything-then-whitelist** pattern
  (`/*`, then `!` lines). This is deliberate: it makes it impossible to sweep a
  whole project in by accident
- **Whitelist whole directories** (`!/tools/`), never individual files. `/*` is
  anchored and `*` does not cross `/`, so re-including a directory covers
  everything under it. Re-excluding contents (`/tools/*`) means every future
  script needs a line, and a missing line makes the file invisible to git — it
  never commits, never syncs, and nothing reports it
- Create `repos.tsv` with just the header comments
- Copy `templates/bootstrap.sh` → `~/dev/`, `templates/new-project.sh` → `~/dev/tools/`, `chmod +x`
- Copy `templates/workspace-status.sh`, `templates/catch-up.sh` and `templates/asset-inventory.sh` → `~/dev/tools/`, `chmod +x`
- Copy `templates/workspace-test.sh` → `~/dev/test/`, `chmod +x`
- Whitelist the `tools/`, `test/` and `assets/` **directories** in
  `~/dev/.gitignore`, not the individual scripts
- Write a short `README.md`
- **Run `test/workspace-test.sh` and show them the result**
- `git init`, commit, **ask**, then `gh repo create dev-workspace --private --source=. --push`
- Append two rows to `repos.tsv`: `claude-config`, and `.` for the workspace repo
  itself. The `.` row is what lets `~/dev` keep itself current — fetched,
  fast-forwarded and pushed when the tree is clean, never committed for them
- Commit and push those rows

### 6. First project

Use the script, so they see the intended path:

```sh
~/dev/tools/new-project.sh <name>
```

**Ask before you run it.** The script normally asks before creating the GitHub
repo, but that prompt needs a terminal — and you do not have one, so it creates
the repo without asking. That is deliberate: a script run non-interactively used
to read the silence as "no" and leave the project unsynced on one machine. It
does mean the confirmation is now yours to get, not the script's. `--no-remote`
makes a local-only project if they would rather wait.

### 7. Verify and hand over

```sh
ls -la ~/.claude/{CLAUDE.md,settings.json,skills,tasks}   # all show ->
gh repo list --limit 10                                # private only
cd ~/dev && ./bootstrap.sh --dry-run                   # every line "exists"
cat ~/dev/repos.tsv
~/dev/claude-config/test/sync-test.sh                  # must pass
~/dev/test/workspace-test.sh                           # must pass
~/dev/tools/workspace-status.sh now                    # near-silent when healthy
```

Explain the last one: **silence means level.** The report only speaks when
something needs them, which is why a quiet session start is the good outcome.

Then tell them: read `06-DAILY-USE.md`, and `07-SECOND-MACHINE.md` when they add
a computer. If they have not yet read `01-WORKING-WITH-AN-AGENT.md`, point them
there first — it is the one that explains why any of this exists.

---

## CLAUDE.md content

Write `~/dev/claude-config/CLAUDE.md` covering, concisely:

- **Workspace:** everything in `~/dev/<project>`; memory is keyed to absolute
  path, so never relocate a project without renaming its key under
  `~/.claude/projects/`
- **Sync:** code moves by git remote only, never a file-sync service
- **Publishing:** everything private; `gh repo create` always `--private`; never
  flip visibility, because `git rm` doesn't remove history — publishing means a
  new repo
- **Never commit:** build output, `node_modules/`, `.env` and secrets,
  `.DS_Store`, `.claude/settings.local.json`
- **No absolute paths containing a literal username in source** — they break on
  any other machine, and they break hardest across platforms, where the home
  directory is `/Users/<name>` on macOS and `/home/<name>` on Linux and WSL2

Keep it under ~60 lines. It loads in every session; length is a real cost.

---

## Things that will go wrong

| Symptom | Cause | Fix |
|---|---|---|
| Symlink is a real file | Something replaced it | Move the file into `claude-config/`, re-run `install.sh` |
| `gitignore` rule not matching in a subfolder | Pattern has a slash, so it's root-anchored | Prefix with `**/` |
| Push asks for a password | Credential helper not configured | Re-run `gh auth login`, accept the offer |
| `gh repo create` fails | Name taken, or not authenticated | Choose another name; check `gh auth status` |
| Memory not syncing | No remote, or the sync hit something it won't guess about | Check the remote exists; run `claude-config/bin/sync.sh status` |
| A new script never reaches the other machine | `~/dev/.gitignore` whitelists files instead of directories | Whitelist the directory; the session-start report also flags this |
| `install.sh` made a dangling `tasks` symlink | Ran from a copy missing `bin/lib-paths.sh` | Copy all four `bin/*.sh` templates |
| `$'\r': command not found` | Script picked up Windows line endings (WSL2) | `sed -i 's/\r$//' <script>`; consider `git config --global core.autocrlf input` |
| Everything is inexplicably slow (WSL2) | Workspace is on `/mnt/c/` | Move it to `~/dev` on the Linux filesystem |
| `brew: command not found` on Linux | Homebrew assumed | Use `apt`/`dnf`/`pacman` — see the precondition table |
| Claude has no memory of a project they worked on | Two Claude Code installs (Windows + WSL2) | Keep the WSL2 one, remove the other |

---

## Do not

- Do not create **public** repos. Ever. Not even "just to test"
- Do not `git init` in `$HOME`
- Do not copy credentials between machines
- Do not commit anything you have not looked at — check for `.env`, keys, and
  large binaries before the first commit
- Do not rewrite the template scripts to be "cleaner". They handle failure modes
  that are not obvious from reading them
- Do not skip verification because a command exited 0
- Do not assume macOS. Check `uname -s` before reaching for `brew` or
  `xcode-select`
- Do not try to make the bash tooling run on native Windows. Send them to
  `04-ENVIRONMENT.md` instead

---

## When they ask "why"

Point them at `03-WHY.md` rather than improvising. The short version:

- **git** gives a timeline and an undo that works
- **GitHub** makes the work exist somewhere other than one laptop
- **`claude-config`** makes Claude's project knowledge survive sessions and
  machines
- **the manifest** makes a second machine three commands instead of fifteen
  remembered steps
