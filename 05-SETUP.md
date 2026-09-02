# Setup — from zero

macOS, Linux, or WSL2 on Windows. Allow 45–60 minutes. Read `01-WORKING-WITH-AN-AGENT.md` and
`03-WHY.md` first, and `04-ENVIRONMENT.md` if you're on Windows.

Anything in `code font` is typed into a terminal. Lines starting with `#` are
comments — don't type them.

**Which terminal:**

| You're on | Open |
|---|---|
| macOS | **Terminal** (⌘-Space, type "Terminal") |
| Windows + WSL2 | **Ubuntu** from the Start menu — *not* PowerShell, *not* CMD |
| Linux | Your terminal |

Steps 1–3 differ by platform. **Steps 4 onward are identical everywhere** — from
step 4 you're in a Unix shell no matter which machine you're sitting at, which is
the point.

> Prefer to have Claude do this with you? Do steps 1–3, then point it at
> `AGENT-INSTRUCTIONS.md`.

> **Native Windows without WSL?** This kit's tooling is bash scripts, and they
> won't run. Either follow `04-ENVIRONMENT.md` and install WSL2, or use Claude
> Code on its own without the workspace automation — it works fine, you just
> maintain the git habits by hand.

---

## Step 1 — A working toolchain

### macOS

```sh
xcode-select --install
```

A dialog appears; click Install. If it says already installed, good. This gives
you `git` and the compilers other tools expect.

Then Homebrew, which installs everything else. Skip if `brew --version` already
works:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Read the "Next steps" it prints.** On Apple Silicon it asks you to add Homebrew
to your PATH, and skipping that is the single most common reason the next command
fails.

```sh
brew install gh
```

### Windows (WSL2) and Linux

If you haven't installed WSL2 yet, `04-ENVIRONMENT.md` section 5 covers it —
`wsl --install` in an Administrator PowerShell, then reboot.

In your Ubuntu terminal:

```sh
sudo apt update && sudo apt install -y git curl
```

Then the GitHub CLI, which isn't in Ubuntu's default repositories:

```sh
sudo apt install -y gh
```

If that reports the package can't be found, your Ubuntu is older than the version
that carries it — follow the official instructions at
<https://github.com/cli/cli/blob/trunk/docs/install_linux.md>.

### Everyone — check

```sh
git --version        # expect git version 2.x
gh --version         # expect gh version 2.x
```

---

## Step 2 — Claude Code

The install is now the same command on macOS, Linux and WSL:

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

This installs a self-contained binary — no Node.js needed — and it keeps itself
updated in the background. On macOS you can use `brew install --cask claude-code`
instead if you'd rather Homebrew managed it, but Homebrew installs don't
auto-update.

> You may find older guides saying `npm install -g @anthropic-ai/claude-code`.
> That still works and installs the same binary, but it's no longer the
> recommended route and it needs Node 22+.

Check it:

```sh
claude --version     # prints something like 2.1.211 (Claude Code)
claude doctor        # a read-only health check of the install and settings
```

`claude doctor` is worth remembering. It diagnoses installation and settings
problems without starting a session, and it's the first thing to run when
something is odd later.

**One thing to know before you go further:** Claude Code needs a paid plan — Pro,
Max, Team, Enterprise, or an API/Console account. The free Claude.ai tier does not
include it. If your university provides access, that's what to use; check what
your institution offers before paying for anything yourself.

You'll log in at the end of step 10, not now.

---

## Step 3 — A GitHub account

Skip if you have one. Otherwise sign up at <https://github.com>.

**Choose a username you'll keep** — ideally your name. It becomes part of every
project URL, and it's what people see. You *can* rename later, but the old name is
released immediately for anyone to claim.

Students: apply for the **GitHub Student Developer Pack** at
<https://education.github.com/pack>. It's free with a `.edu` address and includes
things you'd otherwise pay for. Unlimited private repos are free for everyone
regardless, so this setup costs nothing either way.

Then, in your terminal:

```sh
gh auth login
```

Choose: **GitHub.com** → **HTTPS** → **Login with a web browser**. Say **yes** when
it offers to use `gh` as your credential helper — that's what stops git asking for
a password constantly.

> **In WSL2**, this opens a browser on the Windows side. That's expected and it
> works. If it can't open one, it falls back to printing a code and a URL —
> copy the URL into any browser.

```sh
gh auth status       # should show your username
```

---

## Step 4 — Tell git who you are

Every commit records a name and email. Use GitHub's **noreply** address so your
real email is never embedded in a repo that might one day be public.

Find your numeric account ID:

```sh
gh api user --jq '.id'
```

Then, substituting that number and your username:

```sh
git config --global user.name  "Your Name"
git config --global user.email "1234567+yourusername@users.noreply.github.com"
```

GitHub still links commits to you — it matches on the **numeric ID**, which never
changes, even if you rename later.

```sh
git config --global --list | grep user      # check
```

---

## Step 5 — A global ignore file

Some files should never be committed anywhere: OS clutter, editor settings,
downloaded dependencies. The list below covers macOS, Linux and Windows, so it
works unchanged on every machine you use.

```sh
cat > ~/.gitignore_global <<'EOF'
# macOS
.DS_Store
._*
.Spotlight-V100
.Trashes

# Linux
*~
.directory
.Trash-*

# Windows — you'll meet these if a file ever crosses from the Windows side
Thumbs.db
desktop.ini

# Editors
.vscode/
.idea/
*.swp
*~

# Claude Code machine-local files
**/.claude/settings.local.json
**/.claude/*.lock
EOF

git config --global core.excludesfile ~/.gitignore_global
```

> The `**/` prefix matters. Without it the rule only applies at the top of a
> repo, not in subfolders. This catches people out constantly.

---

## Step 6 — The workspace folder

```sh
mkdir -p ~/dev/tools ~/dev/test ~/dev/assets
cd ~/dev
```

**Everything goes in `~/dev`.** Claude Code's per-project memory is tied to each
project's full path, so a predictable location is what makes memory survive and
what lets a second machine find it. `01-WORKING-WITH-AN-AGENT.md` explains why.

> **WSL2 users, the one that bites:** `~/dev` here means the Linux home
> directory — check with `pwd`, which should print `/home/yourname/dev`. If it
> prints anything starting `/mnt/c/`, you're on the Windows drive. Everything
> will work and everything will be slow, in a way that's hard to diagnose later.
> Move it now: `mv /mnt/c/path/to/dev ~/dev`.
>
> To reach these files from Windows Explorer, use `\\wsl$` in the address bar, or
> just type `explorer.exe .` from the Ubuntu terminal.

---

## Step 7 — The config repo

This holds Claude's settings, memory, task lists and session digests, so all of it
can sync.

```sh
mkdir -p ~/dev/claude-config/{bin,memory,skills,test}
cd ~/dev/claude-config
git init
```

Copy from `templates/` in this starter kit:

| From `templates/` | To |
|---|---|
| `install.sh`, `sync.sh`, `adopt-memory.sh`, `lib-paths.sh`, `digest.sh` | `~/dev/claude-config/bin/` |
| `sync-test.sh` | `~/dev/claude-config/test/` |
| `path-map.tsv` | `~/dev/claude-config/` |

Then make them executable and **run the tests before you rely on any of it**:

```sh
chmod +x bin/*.sh test/*.sh
./test/sync-test.sh          # 0 failed
```

The pass count grows as tests are added, so don't match it against a number —
**`0 failed` is the whole result.** Anything else means stop and fix it before
you rely on any of this.

That test builds two fake machines and a fake GitHub, then plays out the ways
syncing goes wrong — a crashed session, two sessions at once, both machines
editing the same note, a half-finished merge. It takes a few seconds and it is the
difference between trusting this and hoping.

One small file matters more than it looks:

```sh
# A task lock belongs to a running process on one machine, so it should never
# travel to the other one.
printf '.DS_Store\ntasks/**/.lock\n' > .gitignore
```

Now `CLAUDE.md` — conventions Claude reads in **every** session:

```sh
cat > ~/dev/claude-config/CLAUDE.md <<'EOF'
# Working conventions

## Workspace
All projects live in `~/dev/<project>`. Claude Code keys project memory to the
absolute path, so never relocate a project without also renaming its key
directory under `~/.claude/projects/`.

Code moves between machines through git remotes only — never a file-sync
service, which corrupts build state and cannot merge conflicts.

## Publishing
Everything is private. `gh repo create` always takes `--private`.

Never flip a repo from private to public: deleting a file only clears the tip,
so changing visibility exposes the entire history. Publishing means creating a
NEW repo containing only what was meant to be shared.

## Never commit
Machine-local or generated files: `.DS_Store`, build output, `node_modules/`,
`.env`, `.claude/settings.local.json`.

Absolute paths containing a literal username do not belong in source — they
break on any other machine.
EOF
```

First commit, and the private remote:

```sh
cd ~/dev/claude-config
git add -A
git commit -m "Claude configuration and memory"
gh repo create claude-config --private --source=. --push
```

Link it into place:

```sh
~/dev/claude-config/bin/install.sh
ls -la ~/.claude/CLAUDE.md        # should show -> ~/dev/claude-config/CLAUDE.md
ls -la ~/.claude/tasks            # should show -> ~/dev/claude-config/tasks
```

**Never run Claude Code before?** Then `~/.claude` may not exist at all, and that
is fine — `install.sh` creates what it needs, and creates the empty `skills/` and
`tasks/` folders in the repo rather than pointing a symlink at nothing.

Your prompt history (`~/.claude/history.jsonl`) stays **local to each machine** on
purpose. What travels instead is a digest of each session, which is more useful and
far smaller.

---

## Step 8 — Automatic syncing

Four hooks do the work: two at session start, two at session end. You never run a
sync command.

```sh
cat > ~/dev/claude-config/settings.json <<'EOF'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/dev/claude-config/bin/sync.sh\" pull || true", "timeout": 30 } ] },
      { "hooks": [ { "type": "command", "command": "\"$HOME/dev/tools/workspace-status.sh\" report || true", "timeout": 20 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/dev/claude-config/bin/digest.sh\" || true", "timeout": 15 } ] },
      { "hooks": [ { "type": "command", "command": "\"$HOME/dev/claude-config/bin/sync.sh\" push || true", "timeout": 30 } ] }
    ]
  }
}
EOF

mkdir -p ~/.claude          # may not exist yet if you have never run Claude Code
ln -sf ~/dev/claude-config/settings.json ~/.claude/settings.json
```

Already have a `settings.json`? Move it into `claude-config/` first, add these
hooks to the existing `hooks` object, then symlink.

What they do:

- **`sync.sh pull`** — commits any memory this machine wrote, rebases onto the
  remote, pushes, and links memory for projects created on your other machine. It
  captures at *both* ends, so a session that crashes doesn't strand its notes.
- **`workspace-status.sh report`** — checks the project you're in for real, then
  reports anything out of sync. **Prints nothing when everything is level.**
- **`digest.sh`** — writes a small Markdown record of the session: what you asked,
  which files changed, how long it took. That is what lets the other machine see
  what this session was for, since the conversation itself does not travel.
- **`sync.sh push`** — the same capture, then a push.

These are written to never fail and never hang: every path a hook can reach
exits 0, git gets a short network timeout, and a missing remote is a valid
state. Each hook adds `|| true` on top of that. A broken hook is worse than
slightly stale memory.

(The scripts do exit non-zero if you hand them a subcommand they don't have —
that's for you at a prompt, not for the hooks, which only ever pass valid ones.)

---

## Step 9 — The workspace repo

This tracks the *map*: which projects exist and where.

```sh
cd ~/dev

cat > .gitignore <<'EOF'
# Ignore everything, then whitelist. A new project can never be swept in by an
# accidental `git add -A`.
#
# WHITELIST DIRECTORIES, NOT FILES. `/*` matches only top-level entries and `*`
# does not cross `/`, so re-including a directory covers everything inside it.
# If you instead re-exclude the contents (`/tools/*`), every new script needs a
# line here — and a missing line makes the file invisible to git: never
# committed, never synced, with nothing to tell you.
/*

!/README.md
!/.gitignore
!/repos.tsv
!/bootstrap.sh
!/tools/
!/test/
!/assets/
/assets/*.txt

.DS_Store
EOF

cat > repos.tsv <<'EOF'
# PATH<TAB>KIND<TAB>URL     KIND: mine | reference
# URL "-" means no remote yet.
EOF
```

Copy the rest of the scripts from `templates/`:

| From `templates/` | To |
|---|---|
| `bootstrap.sh` | `~/dev/` |
| `new-project.sh`, `workspace-status.sh`, `catch-up.sh`, `asset-inventory.sh` | `~/dev/tools/` |
| `workspace-test.sh` | `~/dev/test/` |

```sh
chmod +x ~/dev/bootstrap.sh ~/dev/tools/*.sh ~/dev/test/*.sh
~/dev/test/workspace-test.sh        # 0 failed
```

Then the repo and its remote:

```sh
cd ~/dev
git init
git add -A
git commit -m "Workspace: the map of ~/dev"
gh repo create dev-workspace --private --source=. --push
```

Record `claude-config` and the workspace itself in the manifest:

```sh
printf 'claude-config\tmine\t%s\n' "$(git -C ~/dev/claude-config remote get-url origin)" >> ~/dev/repos.tsv
printf '.\tmine\t%s\n' "$(git -C ~/dev remote get-url origin)" >> ~/dev/repos.tsv
git add repos.tsv && git commit -m "Add the config and workspace repos to the manifest" && git push
```

That `.` row is what lets the workspace keep itself current: from now on `~/dev`
is fetched, fast-forwarded and pushed for you whenever your tree is clean. It
will never commit for you — writing you haven't finished stays yours.

---

## Step 10 — Your first project

```sh
~/dev/tools/new-project.sh myproject
```

It scaffolds the project, commits, offers to create a **private** GitHub repo,
records it in the manifest, and commits that.

**Run it before you start working in a folder**, not after — it writes a
`CLAUDE.md`, `.gitignore` and `.publish-exclude`, and while it moves an existing
file aside rather than overwriting it, you'd then be merging your own file back by
hand.

If you forget and just make a folder, the next session will notice and offer to
run it for you.

```sh
cd ~/dev/myproject
claude
```

Log in when prompted — a browser opens, you authorise, and you're back.

---

## Verify

```sh
ls -la ~/.claude/{CLAUDE.md,settings.json,skills,tasks}   # all show ->
gh repo list --limit 10                               # your private repos
cat ~/dev/repos.tsv                                   # your projects
cd ~/dev && ./bootstrap.sh --dry-run                  # all "exists"
~/dev/claude-config/test/sync-test.sh                 # 0 failed
~/dev/test/workspace-test.sh                          # 0 failed
~/dev/tools/workspace-status.sh now                   # a live report
```

The last one is the interesting check: if everything is in order it says almost
nothing. That's correct.

**On WSL2, one extra check worth doing now** — confirm you're where you think:

```sh
pwd                  # /home/yourname/dev, NOT /mnt/c/anything
```

Next: **`06-DAILY-USE.md`**.

---

## If something went wrong

| Symptom | Fix |
|---|---|
| `gh: command not found` | **macOS:** Homebrew's PATH step was skipped — re-read its "Next steps". **WSL/Linux:** `sudo apt install gh` |
| `claude: command not found` | Open a new terminal first — the installer adds `~/.local/bin` to your PATH and existing shells don't have it yet. Still failing? Run `claude doctor`, or re-run the install command |
| Anything odd about the install | `claude doctor` — read-only diagnostics, no session started |
| `claude` says you need a subscription | Claude Code needs a paid or institutional plan; the free Claude.ai tier doesn't include it |
| Everything is inexplicably slow (WSL2) | Your project is on `/mnt/c/`. Move it to `~/dev` on the Linux side |
| `\r: command not found` running a script | The file picked up Windows line endings. `sed -i 's/\r$//' path/to/script.sh` |
| Git asks for a password on push | Re-run `gh auth login` and accept the credential-helper offer |
| `install.sh` reports permission denied | `chmod +x ~/dev/claude-config/bin/*.sh` |
| A symlink shows a real file, not `->` | Move the file into `claude-config/`, then re-run `install.sh` |
| A test fails | Stop and read which assertion. Don't build on top of a failing sync |
| Session start says a file "will never sync" | Your `.gitignore` is missing a directory whitelist — add the directory, not the file |
