# Adding a second computer

The payoff. Once set up, sitting down at the other machine means opening Claude and
having everything — code, memory, task lists, and the questions you asked
yesterday.

Allow ~20 minutes plus download time.

**The two machines don't have to run the same system.** A Mac and a Linux box,
or a laptop and WSL2 on a desktop, work together fine — everything that syncs is
git repos and text files. Where a step differs, this document says so per
platform; where it doesn't, the command is the same everywhere.

---

## The one thing worth matching

**Use the same account name on both machines**, so your projects sit at the same
absolute path.

Check on each:

```sh
id -un        # your account name
echo "$HOME"  # where it puts your home directory
```

Whether the paths can actually match depends on which two systems you're
pairing, because home directories live in different places: `/Users/alex` on
macOS, `/home/alex` on Linux **and** on WSL2, which is Linux underneath.

| Your two machines | Same absolute path? | What to do |
|---|---|---|
| Mac + Mac | Yes, `/Users/alex/dev` | Match the account name; nothing else |
| Linux + Linux | Yes, `/home/alex/dev` | Match the account name; nothing else |
| WSL2 + WSL2 | Yes, `/home/alex/dev` | Match the *Linux* account name — it need not match your Windows one |
| WSL2 + Linux | Yes, `/home/alex/dev` | Match the account name; WSL2 is Linux here, so nothing is special |
| Mac + Linux or WSL2 | **No** — `/Users` vs `/home` | Expected, and handled. Add a row to `path-map.tsv` |

Only the last row needs anything. A Mac paired with Linux or WSL2 **cannot**
share an absolute path no matter what you name the accounts, because they differ
one level above the account name. That's what `path-map.tsv` is for, and matching
the account name is still worth doing — it keeps the part below the root
identical, which is the part the map lines up.

Claude Code stores per-project memory keyed to each project's absolute path. If one
machine is `/Users/alex/dev/robot` and the other `/Users/adempsey/dev/robot`, those
are different keys.

The setup carries a small map file (`claude-config/path-map.tsv`) so a machine that
*can't* use the same location still finds its memory: memory folders are named by
their path **relative** to your workspace root, so both machines agree even if the
roots differ. Set that machine's root there and everything works.

> **Put a custom root on a machine-name row, never on the `*` row.** That file
> syncs, so a `*` row naming one machine's location becomes every machine's. Rows
> pointing at a directory that doesn't exist locally are ignored for that reason,
> so the mistake falls back to `~/dev` rather than losing your memory quietly.

The rest of this document assumes you've matched the account name.

---

## Setup

### 1. Prerequisites

Same as `05-SETUP.md` step 1, condensed. **macOS:**

```sh
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh
```

On Apple Silicon, read the "Next steps" Homebrew prints — it asks you to add
itself to your PATH, and skipping that is why `brew install gh` fails.

**Windows (WSL2) and Linux** — in your Ubuntu terminal (`04-ENVIRONMENT.md`
section 5 covers installing WSL2 if you haven't):

```sh
sudo apt update && sudo apt install -y git curl gh
```

If `gh` can't be found, your Ubuntu predates it in the default repositories —
see <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>.

**Then Claude Code — the same command everywhere:**

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

**Check, on any platform:**

```sh
git --version && gh --version && claude --version
```

### 2. Sign in to GitHub

```sh
gh auth login          # GitHub.com → HTTPS → browser; accept credential helper
gh auth status
```

**Do not copy credentials from the other machine.** They live in the platform's
own credential store — Keychain on macOS, `gh`'s config or a helper like
`libsecret` on Linux and WSL2 — and a hand-copied entry fails in confusing ways.
Signing in fresh takes a minute.

> **In WSL2**, `gh auth login` opens a browser on the Windows side. That's
> expected; finish the login there and the Ubuntu terminal picks it up.

### 3. Git identity — the same on both

```sh
git config --global user.name  "Your Name"
git config --global user.email "1234567+yourusername@users.noreply.github.com"
```

Use the *same* values as the first machine, or your history shows two authors.

Recreate the global ignore file (`05-SETUP.md` step 5) — that's the reliable
route, and it's a two-minute job. If both machines are on the same network and
you have SSH access, you can copy it instead:

```sh
scp othermachine:~/.gitignore_global ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

The `.local` hostnames macOS resolves automatically need `avahi-daemon` on
Linux, and don't reach a WSL2 instance at all without port forwarding. If `scp`
doesn't connect, don't debug it — just recreate the file.

### 4. Clone the workspace and everything in it

```sh
git clone https://github.com/YOURNAME/dev-workspace.git ~/dev
cd ~/dev
./bootstrap.sh
```

`bootstrap.sh` reads `repos.tsv` and clones every project to the right path. It
**clones only** — it never pulls — so it's safe to re-run to pick up projects added
since. For updates, use `catch-up.sh`.

### 5. Link Claude's config and memory

```sh
~/dev/claude-config/bin/install.sh
```

This links `CLAUDE.md`, settings, skills, per-project memory and task lists into
`~/.claude`. Your prompt history stays local to each machine by design; what travels
between them is a digest of each session.

### 6. Prove it works before trusting it

```sh
~/dev/claude-config/test/sync-test.sh      # 0 failed
~/dev/test/workspace-test.sh               # 0 failed
```

### 7. Log in to Claude Code

```sh
cd ~/dev/someproject
claude
```

Then test that memory actually arrived — ask something only your notes would know:

> What do you know about this project so far?

If it answers with real specifics, everything worked.

### 8. Name the machines differently

Sync commits are stamped with the computer name. If both machines have the same
name you can't tell which wrote what.

| Platform | How |
|---|---|
| macOS | System Settings → General → About → Name |
| Linux | `sudo hostnamectl set-hostname studio-linux` |
| WSL2 | Add `[network]` and `hostname = studio-wsl` to `/etc/wsl.conf`, then `wsl --shutdown` in PowerShell |

**WSL2 users, this one matters more than it looks.** A WSL2 instance inherits
the Windows computer name until you set it, and fresh Windows installs are often
named alike. Two WSL2 machines can therefore both report the same name — which
also makes `path-map.tsv` unable to tell them apart, since it keys on exactly
this name. Set it on at least one of them.

Check what the machine currently reports:

```sh
scutil --get ComputerName 2>/dev/null || hostname -s
```

That's the same resolution `path-map.tsv` uses, so whatever it prints is the
name to put in a row there.

### 9. Register this machine's big files

```sh
~/dev/tools/asset-inventory.sh scan
git -C ~/dev add assets && git -C ~/dev commit -m "Inventory this machine's assets" && git -C ~/dev push
```

Now each machine can see what large files only exist on the other one.

---

## Working across two machines

The rhythm:

1. **Finish on machine A:** commit and push your code. Memory, tasks and history go
   on their own.
2. **Start on machine B:** open Claude in the project. If anything needs pulling,
   the session-start report says so — and Claude can do it for you.

You don't run a sync command on either machine. When something can't be handled
safely, you get one line about it.

### What syncs, and what doesn't

| Thing | Syncs? | How |
|---|---|---|
| Your code | Yes | You commit and push; `catch-up.sh` pulls |
| Claude's memory | Yes | Automatic, both ends of every session |
| Task lists, session digests | Yes | Part of `claude-config` |
| `CLAUDE.md`, settings, skills | Yes | Part of `claude-config` |
| The workspace map (`repos.tsv`, docs) | Yes | Fetched, fast-forwarded and pushed when your tree is clean |
| **Conversation transcripts** | **No** | They stay on the machine that made them |
| **Prompt history** | **No** | Machine-local; the digest carries what matters |
| Large binaries, build output | No | Deliberately excluded — the *list* syncs instead |

Memory carries the conclusions, and a digest records what each session did. Only the
conversation itself stays behind — see *"What did I do on the other computer?"* in
`06-DAILY-USE.md`.

### New project on the other machine?

Its manifest row arrives on its own, and the session-start report tells you the
project isn't here yet. Then:

```sh
~/dev/tools/catch-up.sh
```

Its memory is linked automatically — before anything writes there, which is what
keeps the two machines from creating two separate sets of notes for one project.

### The one conflict you'll hit

Work on both machines without pushing in between and git will refuse to merge
automatically. The setup handles this conservatively: rather than guessing, it
stops, leaves both copies intact, and tells you at the next session start.

Fix by pulling before you start and pushing when you finish. When it does happen,
ask Claude — resolving a conflict is a five-minute job with help and an anxious hour
without.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Claude has no memory of a project | Path mismatch | `id -un` on both; confirm the project is at the same path, or set this machine's root in `claude-config/path-map.tsv` |
| `bootstrap.sh` says "no remote yet" | Project never pushed | Push it on the first machine; the manifest URL updates |
| Push rejected | Other machine pushed first | `git pull` then push; the memory sync recovers from this by itself |
| Session start prints a `claude-config:` line | Memory sync hit something it wouldn't guess about | `~/dev/claude-config/bin/sync.sh status`, then resolve by hand |
| `no longer symlinked into claude-config` | Some tool replaced a symlink with a real file | Re-run `install.sh` — it backs up what it finds first |
| A project is behind and you're in it | Normal | Ask Claude to pull it, or `git pull --ff-only` |
| Nothing ever reports, and `~/dev/tools/` is empty | This machine hasn't picked up the workspace tooling yet | It installs itself within a session or two; `git -C ~/dev pull` does it now |
| Sessions won't resume from the other machine | Transcripts don't sync, by design | Use memory and `CLAUDE.md` for continuity |
| Both machines stamp sync commits with the same name | Step 8 skipped, or WSL2 still using the Windows name | Set it per the table in step 8; `hostname` shows the current one |
| `~/dev` on WSL2 isn't the folder you expected | You're in `/mnt/c/Users/...`, the Windows side | `cd ~` should land in `/home/<you>`; if not, you opened PowerShell rather than Ubuntu |
