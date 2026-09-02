# Why this setup exists

Read this before building anything. Copying a setup you don't understand gets
you something you can't fix the first time it breaks.

`01-WORKING-WITH-AN-AGENT.md` covered how agents actually work, and left one
problem open: an agent forgets everything when the session ends, and what
survives is whatever got written to a file. This document covers the **tools**
that solve that — git, GitHub — and then why this particular setup is built
around them the way it is. It's the shorter of the two.

Everything here works on **one computer**. A second machine is a bonus this
design happens to make easy, not the reason to do it.

---

## The two problems

### Problem 1: your work only exists in one place

Your project lives in a folder on your laptop — the code, and equally the notes,
sources and drafts around it. If the laptop dies, is stolen, or you delete the
wrong folder, it's gone. Copying folders around (`project_v2`,
`project_final`, `project_final_ACTUAL`) is not a solution — you end up unable to
say which is current or what changed between them.

Cloud sync (iCloud, Dropbox, Google Drive) seems like the answer and is actively
bad for code. It syncs mid-save, corrupts build folders, and when the same file
changes in two places it either picks one or leaves you a "conflicted copy" with
no way to merge the actual changes.

### Problem 2: your AI assistant forgets everything

Claude Code is genuinely useful — it reads your code, makes changes, runs
commands. But by default each session starts fresh. Everything you explained
last week — why the board uses that voltage, which approach you already tried and
abandoned, what the hardware quirk was — has to be re-explained.

This is not a small tax. Re-explaining a project costs you time at the start of
every session, and it costs you quality — an assistant that doesn't know why you
rejected an approach will confidently suggest it again.

**Different problems, different tools.** Git and GitHub solve the first. A small
amount of setup around Claude Code solves the second. (And if you ever add a
second computer, the same two solutions cover that too, for free — see
`07-SECOND-MACHINE.md` when the time comes.)

---

## What git actually is

Git records **snapshots** of your project over time. A snapshot is called a
**commit**, and each one stores what changed, when, and a message saying why.

That gives you:

- **A timeline.** See what the project looked like last Tuesday.
- **Undo that actually works.** Broke something? Return to any earlier commit.
- **A record of reasoning.** `git log` becomes a history of decisions, if you
  write real commit messages.
- **Fearless experimentation.** Try the risky refactor; you can always go back.

Git runs entirely on your computer. It is not GitHub, and it does not back
anything up by itself.

### The vocabulary you need

| Term | Meaning |
|---|---|
| **repository (repo)** | A folder git is tracking |
| **commit** | One saved snapshot, with a message |
| **staging** | Choosing which changes go in the next commit (`git add`) |
| **remote** | A copy of the repo somewhere else — usually GitHub |
| **push** | Send your commits to the remote |
| **pull** | Fetch commits from the remote |
| **clone** | Download a repo, with its full history |
| **fast-forward** | A pull with nothing to merge — your copy just moves up to match. Cannot conflict, cannot lose work |
| **branch** | A parallel line of work. You can ignore this for a long time |

`fast-forward` is worth knowing early, because this setup will only ever pull
that way on your behalf. Anything more complicated, it hands to you.

---

## What GitHub adds

GitHub stores a copy of your repo on the internet. That copy gives you:

- **Real backup.** Laptop dies, `git clone`, you're back — history and all.
- **A second machine.** Clone on another computer, push and pull to stay level.
- **A record you didn't have to maintain.** Every commit, timestamped.
- **The option of publishing.** Only if you ever want it.

### Private by default, and why it matters

A GitHub repo is either **private** (only you) or **public** (the entire
internet, plus every AI training scraper).

Everything here is **private**. Publishing is a separate, deliberate decision
made later, per project.

There's a subtlety that catches almost everyone:

> **Deleting a file does not remove it from a repository.**

Git keeps history. If you commit a file containing your API key and delete it in
the next commit, the key is still in the repo — anyone can read it from the
earlier commit. So if you take a private repo full of personal notes and flip it
to public, **everything you ever committed becomes visible**, not just the current
files.

This drives one hard rule you'll see throughout:

> **Never flip a repo from private to public.** To publish, build a *new* repo
> containing only what you meant to share.

---

## What Claude Code is

An AI assistant that works in your terminal, in your project folder. It reads
your files, writes code, runs commands, and explains things. Unlike a chat
window, it sees the actual project — and unlike autocomplete, it can take a task
and work through it, checking its own results as it goes.

That last part is what makes it an **agent** rather than a chatbot, and it
changes how you work with it — which is what `01-WORKING-WITH-AN-AGENT.md` was
entirely about, so this section stays short.

### The files that make it much better

**`CLAUDE.md`** — a file in your project that Claude reads automatically at the
start of every session. Put in it what a new collaborator would need: what the
project is, how to build it, rules that must not be broken, mistakes not to
repeat. Written once, applied every session.

**Memory** — notes Claude keeps about a project between sessions, stored outside
your project folder in `~/.claude/`.

**Task lists** — what you were working on.

**Session digests** — a short file per session recording what you asked and which
files changed.

### The one mechanical detail that shapes everything else

Memory is stored per-project and **keyed to the project's absolute path** — the
full location like `/Users/yourname/dev/robot` (or `/home/yourname/dev/robot` on
Linux and WSL2), with the slashes turned into dashes.

Move or rename the project folder and the memory is orphaned: Claude starts
blank, and nothing tells you why.

Keeping every project at `~/dev/<name>` is the simple way to never have that
happen, and it's why this setup is so particular about where things live. It also
carries a small map file for machines that can't use the same location — but
matching paths is the version least likely to surprise you.

This is the mechanical half of what `01-WORKING-WITH-AN-AGENT.md` described:
the memory it talked about writing down has to be filed somewhere, and the path
is the filing key.

---

## What the setup adds on top

Git, GitHub, and Claude Code are the ingredients. A few small pieces glue them
together:

**1. A workspace folder, `~/dev/`.** Every project in one predictable place, so
paths are consistent and memory keeps working.

**2. A config repo, `claude-config`.** A private repo holding Claude's settings,
per-project memory, task lists and session digests. It's linked into `~/.claude` so
Claude reads it normally without knowing. Because it's a git repo, all of that
syncs between machines — automatically, at the start and end of every session.

**3. A manifest and a bootstrap script.** A plain list of every project and its
GitHub URL, plus a script that clones them all. Setting up a new computer becomes
three commands instead of remembering fifteen projects.

**4. A new-project script.** Starting a project properly means six steps
(initialise, scaffold, commit, create the private remote, record it in the
manifest, save that). Six steps done by hand are six steps to forget. One command
does all of it.

**5. A status report that stays quiet.** At session start, something checks
whether the project you're in is behind, whether a project exists on the other
machine but not this one, and whether anything is uncommitted or unpushed. If
everything is level it prints **nothing**. When it speaks, it means something —
and Claude can act on it, because it sees the report too.

**6. An index of what can't sync.** Video, ROM dumps and datasets don't belong in
git. Rather than pretend otherwise, the setup keeps a *list* of them per machine —
small text files that do sync — so you can see what's only on the other computer
and copy it deliberately.

---

## The design idea worth understanding

Everything automatic in this setup is something that **cannot lose your work**:
fetching, fast-forwarding, creating a symlink, committing Claude's own memory.

Everything that *could* lose work — merging, rebasing, pushing your code,
committing writing you haven't finished — is **reported and left to you**.

So when the setup does nothing, that's not it being lazy; that's the design. It
would rather tell you that three repos are out of sync than guess which version of
a file you meant to keep.

---

## Why bother with all this?

**On the machine you already have**, which is the case that matters:

- Real backup. Laptop dies, `git clone`, you're back — history and all
- An undo that works, at any point in the project's life
- A written record of your reasoning, accumulated as a side effect of working
- An assistant that remembers your projects instead of relearning them every
  Monday
- One place where every idea you've had lives, including the half-finished ones
  and the ones that never became code at all

**Later, if you want them**, two things you get without extra work:

- **A second computer.** Sit down at it, open Claude, and everything is there —
  code, memory, tasks, and a record of what each session did. You don't build
  anything extra for this — it is what the design already does
- **Something to show.** Real project history for an employer, or one project
  published safely without exposing five years of private notes

### The honest costs

- **An hour to set up**, plus learning the ideas.
- **A habit to build.** Committing and pushing your code is still on you.
- **Some of it only pays off later.** The manifest and the sync machinery are
  cheap now and valuable the day you add a machine, reinstall an OS, or come back
  to a project after six months. If that feels like over-engineering for one
  laptop, it partly is — right up until it isn't.
- **Real limits.** Big files don't belong in git. Video, ROM dumps and build
  output stay local — the setup tracks the list, not the bytes.
- **It isn't instant.** Things move at session boundaries, not continuously. Two
  computers editing the same file at the same time will still need you to sort it
  out.

The alternative is folders named `final_v3_REAL` and explaining your project to
Claude from scratch every Monday.

---

Next: **`04-ENVIRONMENT.md`** — where to run all this, and why that's a real
question if you're on Windows.
