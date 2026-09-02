# Daily use

The habits that make the setup worth having.

---

## Working on a project

```sh
cd ~/dev/myproject
claude
```

That's the whole ritual. At session start the setup pulls Claude's memory, links
anything new, checks whether *this* project is behind its remote, and tells you if
something needs you. If everything is level, **it says nothing at all**.

Work as normal. When you've done something worth keeping:

```sh
git add -A
git commit -m "Add PID controller for the motor loop"
git push
```

**Commit when something works**, not once a week. A commit is a save point you
can return to. Small and frequent beats large and rare.

**Write messages your future self can use.** `"fix"` tells you nothing in three
months. `"Fix ADC reading twice per cycle — caused the 2x offset"` tells you
everything.

Claude will commit for you if you ask ("commit this with a message explaining
why"). It's usually better at commit messages than tired humans are.

---

## Reading the session-start report

Silence is the normal case. When a line does appear it starts with `workspace:`
and means one of these:

| What it says | What to do |
|---|---|
| `<project> is N commits behind origin — and it is what you are working in` | Pull before you start. Ask Claude to, or `git pull --ff-only` |
| `<project> is N behind AND has uncommitted changes` | Commit or stash first — pulling there is a merge, which is your call |
| `N project(s) here on the other machine but not this one` | `~/dev/tools/catch-up.sh`, or ask Claude to catch you up |
| `<folder>/ is not a git repo and has no repos.tsv row` | You made a folder by hand. Let it run `new-project.sh` |
| `unpushed: <project> (N)` | Commits exist on this machine only. Push them |
| `N workspace file(s) are gitignored, so they will never sync` | A `.gitignore` whitelist is missing a directory |
| `claude-config: ...` | Memory syncing hit something it wouldn't guess about. See the troubleshooting table in `07-SECOND-MACHINE.md` |

Because Claude sees the same report, "sort that out for me" is usually enough.

---

## Getting current in one command

```sh
~/dev/tools/catch-up.sh --dry-run     # what it would do
~/dev/tools/catch-up.sh               # do it
```

It pulls the workspace map, clones any project that exists on your other machine
but not here, fast-forwards anything behind, and links new memory.

What it **won't** do: touch a repo with uncommitted changes, or merge anything. It
only ever fast-forwards, and prints what it left alone under *"Left alone on
purpose"*. Those are decisions, not chores, so they stay yours.

---

## Starting a new project

```sh
~/dev/tools/new-project.sh robotarm
```

Never `mkdir` a project by hand. The script does six things you'd otherwise have
to remember: initialise, scaffold, commit, create the private remote, record it in
the manifest, save that.

The manifest row is the one that's easy to skip and quietly costly — it's how your
other machine learns the project exists. Once your workspace tree is clean, that
row is pushed for you.

**Run it before you work in the folder.** It writes `CLAUDE.md`, `.gitignore` and
`.publish-exclude`; it moves an existing file aside rather than overwriting it, but
you'd then be merging your own file back by hand.

---

## A folder for every idea

The habit underneath everything else, and the cheapest one on this page.

**Every idea gets a folder in `~/dev`, at the moment you have it.** Not when it's
real. Not when you're sure it's good. When you think of it.

```sh
~/dev/tools/new-project.sh whatever-it-is
```

Most of them will go nowhere — a `README.md` with four lines and a dead end.
That's fine, and it's the point. A folder costs nothing. An idea you had walking
home in March and can't reconstruct in June costs you the idea.

What the habit actually buys:

**Thinking gets somewhere to live.** Open Claude in an empty folder and talk an
idea through for twenty minutes — what it'd take, what's hard about it, whether
it's been done. Then: *"write down what we concluded and what I'd need to
learn."* Now it's a document instead of a mood, and it'll still make sense in
six months.

**You can find it again.** One place. Not Notes, plus a text file on the Desktop,
plus a Discord message to yourself, plus a photo of a napkin.

**The ones that turn real are already in position.** Nothing to migrate. It's
already a repo, already backed up, already known to your other machine. It just
starts getting commits.

**You learn what you actually care about.** Six abandoned folders circling the
same subject is real information about you, and you only get to see it because
you wrote them down.

The rule that keeps it working: **don't curate.** The temptation is to only make
a folder for ideas that deserve one — which means judging an idea at the exact
moment you know least about it. Capture first. Delete later, if ever. Prune once
a term during the weekly-habit pass below, if it bothers you.

Two caveats worth knowing:

- **Ideas that stay ideas can skip the remote.** `new-project.sh` will offer to
  create a private GitHub repo. For a four-line brainstorm you can decline and
  add it later — the manifest row is what matters, and that's what tells your
  other machine the folder exists.
- **A `README.md` with three sentences is a finished document** for this purpose.
  What it is, why you thought of it, what you'd do first. That's enough to
  restart your own brain later, which is the entire job.

---

## What to commit, and what not to

**Commit:** source code, documentation, notes, configuration, small reference
data.

**Don't commit:**

| Kind | Examples | Why |
|---|---|---|
| Build output | `build/`, `dist/`, `.o`, `node_modules/` | Regenerated; large; changes constantly |
| Big binaries | Video, ROM dumps, datasets | Git stores every version forever |
| Secrets | API keys, `.env`, passwords | **Permanent** once committed |
| Machine-local | `.DS_Store`, editor settings | Noise, and conflicts across machines |

Each project has a `.gitignore` for this. Add to it as you go.

> **On secrets:** committing an API key and deleting it next commit does **not**
> remove it. Treat any committed key as compromised — rotate it. The habit that
> prevents this: keep keys in `.env`, ignore `.env`, and commit a `.env.example`
> with the *names* and dummy values.

---

## What not to put here at all

The section above is about what git will punish you for. This one is about
something else: a file can be perfectly fine to commit and still be the wrong
thing to put in this system.

Everything you put in a project has **two audiences beyond you**, and it is worth
being precise about them, because they are commonly confused:

- **GitHub.** A private repo is private *from other GitHub users*. It is not
  invisible to GitHub itself, and it is one compromised account — or one careless
  `--public` — away from being visible to everyone. "Private" is an access
  control, not a guarantee about who can ever read it.
- **The model.** Claude reads your project to be useful; that is the entire
  point. Anything in the folder can be read into context and sent to Anthropic as
  part of a request. This is a reasonable trade for your own code and notes. It
  is a decision you are not entitled to make on someone else's behalf.

So the rule is about **whose material it is**, not how secret it feels:

| Don't put here | Because |
|---|---|
| Another person's personal information | Not yours to hand to a third party, however private the repo |
| An unpublished paper or draft someone shared with you | Shared with *you*, under an expectation you'd be the only reader |
| Data under an NDA, ethics approval, or a data-use agreement | Those agreements usually name where the data may live, and this isn't it |
| Proprietary code from a job or internship | Same, and the consequences land on you |
| Human-subject research data | Nearly always governed by rules that predate any of this |

**Check before you move research data.** Universities and labs generally have a
policy on where it may be stored, and moving it to a personal cloud account in
another country is exactly the move those policies exist to catch. Asking your
supervisor takes a message. Undoing it does not.

There is a specific version of this that catches people using *this* setup, so
it's worth stating on its own:

> **Memory and digests sync too, and they're written without you watching.**
> Claude writes notes to `claude-config/memory/`, and each session leaves a
> digest. Those are committed and pushed automatically. So something you
> mentioned once in conversation — a name, an unpublished result, where a
> sensitive file lives — can end up written down and pushed without you ever
> deciding to commit it. The hooks are doing what they're built to do; the
> judgement about what to say in front of them stays yours.

If you need to *refer* to material you shouldn't store here, keep a pointer
rather than a copy: a note saying what it is and where it lives. That is the same
move the asset inventory makes for large files, for a different reason.

---

## The big files that can't sync

Video, ROM dumps and datasets stay on one machine. Rather than pretend otherwise,
the setup keeps a *list* per machine — small text files that do sync — so you can
see what's where:

```sh
~/dev/tools/asset-inventory.sh scan       # inventory this machine
~/dev/tools/asset-inventory.sh diff       # what's on the other machine but not here
~/dev/tools/asset-inventory.sh plan       # writes the exact rsync command
~/dev/tools/asset-inventory.sh discover   # large ignored files worth tracking
```

`catch-up.sh` re-scans for you. Add directories worth tracking to
`assets/scan-paths.tsv`; don't add build output, and don't add cloned reference
repos — those come back with `git clone`.

`plan` writes a plain-text file list and prints the command. Read it before you
run it.

---

## Using CLAUDE.md well

Each project has a `CLAUDE.md` that Claude reads every session. No other file in
the project changes as much for as little writing.

```markdown
## What this is
A PID motor controller for the ENGR 446 lab, on an STM32L476RG.

## Build and run
    make && make flash

## Rules that must not be broken
- The control loop must complete in under 1ms — don't add allocations
- Never change pin assignments without checking the wiring diagram in docs/

## Mistakes not to repeat
- The ADC needs a 10us settle after channel switch. Reading immediately
  gives the previous channel's value. Cost half a day.
```

That last section is worth more than the rest combined. **When you and Claude
solve something painful, write it down there.** That's how the same bug stops
costing you a day twice.

---

## Letting memory work

Claude keeps per-project notes automatically, and they sync at session
boundaries. Your task lists and session digests ride along too.

- **Ask it to remember explicitly** when something matters: *"remember that the
  sensor needs 10us settle time after switching channels."*
- **Quitting cleanly is tidier but not required.** If a session dies without
  exiting properly, the next one picks up whatever it left behind.
- Memory is for facts about the project; `CLAUDE.md` is for rules. Overlap is fine.

What doesn't follow you is the **conversation itself** — transcripts stay on the
machine that made them. Memory carries the conclusions, which is the part worth
carrying.

---

## "What did I do on the other computer?"

Every session leaves a short digest behind, so that question has an answer even
though the conversation doesn't travel:

```sh
ls ~/dev/claude-config/digests/myproject/          # one file per session, newest last
cat ~/dev/claude-config/digests/myproject/2026-07-29-a1b2c3d4.md
```

Each one records what you asked, which files changed and how often, which machine
it was on, and how long it took. It's written automatically when the session ends.

Because they're plain text, grep is the real interface:

```sh
grep -rl "ADC" ~/dev/claude-config/digests/         # which sessions touched the ADC problem
grep -rh "^- " ~/dev/claude-config/digests/myproject/ | tail -20   # recent questions
```

Two honest limits. The digest is **mechanical** — extracted from the transcript, not
written by Claude — so it tells you *what* happened, not what was concluded; that's
what memory and `CLAUDE.md` are for. And each digest names a session ID, which you
can only resume on the machine that holds that transcript.

Sessions shorter than three prompts don't get a file. That's deliberate: a log full
of `ls` is a log nobody reads.

---

## Running more than one thing at once

You'll hit this in your first week: you give Claude a real task — a refactor, a
test suite, a stubborn bug — and then you wait. Not two seconds. Minutes,
sometimes. And you sit there watching it work, doing nothing.

The fix is **tmux**: one terminal window holding several independent sessions you
switch between instantly.

```sh
brew install tmux          # macOS
sudo apt install tmux      # WSL2 / Linux
```

### The four things it actually buys you

**1. Two projects at once.** Claude working on your coursework in one window,
your own project in another, both live. Each keeps its own conversation and its
own context — which, per `01-WORKING-WITH-AN-AGENT.md`, is the resource you're
really managing. Two focused sessions beat one session you keep switching topics
inside.

**2. Detach and walk away.** This is the one that changes how you work. Close the
terminal, shut the laptop, go to a lecture — the session keeps running and is
exactly where you left it when you come back. You stop being afraid to start
anything long.

**3. It survives a dropped connection.** The moment you SSH into a lab machine, a
university server, or a Raspberry Pi, tmux is the difference between flaky Wi-Fi
killing an hour of work and you not noticing it happened. Start tmux on the
remote machine first, always.

**4. A window per project.** Same idea as a folder per idea, one level up: cheap,
named, and it means putting something down doesn't mean losing your place.

### The commands to start with

Everything in tmux happens after a **prefix key**: `Ctrl-b`, released, then the
next key.

```sh
tmux ls                    # what's already running
tmux new -s robot          # start a session named "robot"
tmux attach -t robot       # reattach to it
tmux kill-session -t robot # end it for good
```

| Keys | Does |
|---|---|
| `Ctrl-b` then `d` | **Detach.** Session keeps running. The important one |
| `Ctrl-b` then `c` | New window |
| `Ctrl-b` then `n` / `p` | Next / previous window |
| `Ctrl-b` then `0`–`9` | Jump to window by number |
| `Ctrl-b` then `%` / `"` | Split the screen vertically / horizontally |

**`tmux ls` first, before you start anything.** Because detached sessions are
invisible — that's the whole point of them — it is genuinely easy to forget one
is there and start a second session for the same project. Now you have two
Claude conversations on the same code, each unaware of the other's edits, and
the confusing part is that neither looks wrong. Checking takes a second.

**Detaching is not quitting.** `Ctrl-b d` leaves the session running, which is
what you want at a lecture and not what you want when the work is finished. A
session you're actually done with needs `tmux kill-session -t robot`, or just
`exit` in its last window. Otherwise they pile up — `tmux ls` a month in is a
list of eleven sessions and no memory of what four of them were for.

Two things worth knowing before you use it:

- **Nothing is saved on the way out.** Killing a session kills whatever is
  running inside it, and the scrollback goes with it. Commit first, or at least
  look at what's in there — `tmux attach -t robot`, then `Ctrl-b d` to step back
  out, costs nothing.
- **`tmux kill-server` ends every session at once.** Useful when things are
  genuinely wedged; a bad way to close one project.

Claude sessions have their own wrinkle here: killing the tmux session ends the
process, not the conversation. Your memory files and handoff notes are on disk
and unaffected — that's exactly why they exist — and `claude --resume` picks up
the transcript on that machine. What you lose is the unsaved scrollback, so if
the session concluded something worth keeping, get it written down before you
kill the window.

A pattern worth copying: one tmux session per project, named after it. Claude in
window 0, a shell for git and running things in window 1, and — for a long job —
window 2 watching the output.

### The honest costs

- **The prefix key is awkward for about a week.** You will fumble it. Then one
  day you won't, and you won't think about it again.
- **Scrollback and copy/paste behave differently.** `Ctrl-b` then `[` enters
  scroll mode; `q` leaves it. Mouse selection needs configuring. This is the part
  people find genuinely annoying at first.
- **It's another thing to learn** while you're already learning git, an agent,
  and possibly Linux.

Which is why this section is here and not in `05-SETUP.md`. **Don't learn tmux
until you've felt the problem it solves.** When you've twice found yourself
waiting on the agent with nothing to do, spend fifteen minutes on it. Before
that, it's just homework.

---

## A weekly habit worth two minutes

```sh
~/dev/tools/workspace-status.sh now
```

That fetches everything and gives you a live answer instead of the cached one:
what's behind, unpushed, uncommitted, or missing on this machine. Uncommitted work
isn't backed up; unpushed commits exist on exactly one computer.

---

## Reading other people's code

You'll want to read libraries and reference projects. **Clone them; don't
download zips.**

```sh
mkdir -p ~/dev/reference
git clone https://github.com/someone/theirproject.git ~/dev/reference/theirproject
```

A zip is a dead snapshot — you can't tell what version it is, can't update it,
and can't see whether a bug is theirs or yours. A clone can `git pull` and shows
you exactly what changed.

Keep them in `~/dev/reference/`, not inside your projects — otherwise you end up
with three copies of the same library and no idea which is current.

**Never commit inside a cloned repo.** It isn't yours.

### Copying from one carries its licence with it

Reading someone's code is free. Copying a piece of it into your project is not
the same act — **the code arrives under whatever licence that repo carries, and
that licence now applies to your project too.** This is not a formality, and
"it was on GitHub" is not a licence. A repo with no licence file at all is the
strictest case: default copyright applies and you have no permission to reuse
it, however public it looks.

So before you paste, look at the repo's `LICENSE` file:

- **MIT, BSD, Apache 2.0** — copy freely; keep the copyright notice with the
  code you took. Apache also asks you to note what you changed.
- **GPL, AGPL** — copying code in can require your whole project to be released
  under the same licence. Fine if that's what you want; a real decision if it
  isn't. AGPL reaches running a service, not just shipping a binary.
- **No `LICENSE` file** — assume you may not copy it. Ask the author, or write
  your own version from what you learned.

Reading it and then writing your own implementation is always fine. That's how
you were going to learn it anyway.

For coursework, a copied block usually still needs a citation even when the
licence permits the copy — the licence and your academic integrity policy are
separate obligations, and the licence does not satisfy the second one. Claude
is good at this question:

> I want to use this function from `<repo>`. What does its licence require of me?

The same reasoning runs in reverse when you publish your own work: whatever you
put in your `LICENSE` file is what you're granting everyone else. This kit's
own `COPYING.md` is a worked example of choosing one.

---

## If you want to publish something

Don't flip the repo to public. History would go public too — every note, every
draft, anything you committed and deleted.

Instead build a **new** repo with only what you meant to share. Ask Claude:

> I want to publish `myproject`. Walk me through building a clean public copy.

---

## Getting help

Claude Code is good at git, especially when you're stuck:

> I committed a file with my API key. What do I do?

> Explain what `git rebase` does and whether I need it.

> Something's wrong with my repo — diagnose it.

Ask it to explain rather than just fix, when you have the patience. The setup is
more useful when you understand it.
