# Starter kit — working with Claude Code and GitHub

A set of documents and scripts that build one workspace: every project in a
private git repo, an AI assistant that remembers them, and a second computer
that stays current on its own.

For an engineering student who writes code for projects and coursework, has maybe
used git a little, and wants a setup that stops losing work and context.

**It is not only for code.** A project here can be a research topic, a subject
you're reading into, or an idea you're still arguing with yourself about. The
same setup that keeps a codebase from getting lost keeps notes, sources,
questions and half-formed conclusions in one place — and gives you something to
think out loud with that remembers what you concluded last week. Plenty of the
folders you end up with will contain no code at all. That's the intended use, not
a misuse.

By the end you'll have every project backed up off your laptop, an AI assistant
that remembers your projects between sessions, and the ability to sit down at a
second computer and pick up where you left off — without typing a sync command.

**macOS, Linux, or Windows.** Windows users: read `04-ENVIRONMENT.md` before
setting anything up — where you run this is a real choice and it's worth ten
minutes.

## Read in this order

| Document | What it covers | Time |
|---|---|---|
| **`01-WORKING-WITH-AN-AGENT.md`** | How to actually work with an agent — the manager frame, tokens and context, memory, handoff documents, and using it to think, research and workshop ideas rather than only to build | 30 min read |
| **`02-LEARNING.md`** | Whether leaning on an agent costs you the thing you're studying for. Read it if you're a student; it's the question the rest of this kit would be dodging otherwise | 20 min read |
| **`03-WHY.md`** | What git, GitHub, and Claude Code actually do, and why this is worth the trouble | 15 min read |
| **`04-ENVIRONMENT.md`** | Where to run this. Mac users skim; Windows users have a real decision | 10 min read |
| **`05-SETUP.md`** | Building it from zero, step by step | 45–60 min |
| **`06-DAILY-USE.md`** | How to actually work once it exists | 10 min read |
| **`07-SECOND-MACHINE.md`** | Adding a second computer | 20 min |
| `08-ADVANCED.md` | Optional: using a second agent (Codex) from inside Claude Code. Only once the rest is habit | 10 min read |
| **`AGENT-INSTRUCTIONS.md`** | Hand this to Claude Code and it builds the setup with you | — |
| `APPENDIX-DUAL-BOOT.md` | Optional reference: running WSL2 and native Linux together. Most people never need it | — |
| `templates/` | The scripts, ready to copy | — |

## Two ways to use this

**Do it yourself:** read `01-WORKING-WITH-AN-AGENT.md` through `04-ENVIRONMENT.md`,
then follow `05-SETUP.md`. You'll understand every piece, which matters when
something breaks.

**Have Claude do it with you:** install Claude Code (`05-SETUP.md` step 2), then:

> Read `AGENT-INSTRUCTIONS.md` in this folder and set up this system for me.

It'll ask for your GitHub username and walk through it. **Still read
`01-WORKING-WITH-AN-AGENT.md` and `03-WHY.md` first** — otherwise you'll have a
system you can't debug. If you're a student, `02-LEARNING.md` too.

## What you get

```
~/dev/
├── README.md, repos.tsv, bootstrap.sh    the map of your workspace
├── tools/                                scripts for common tasks
├── test/                                 tests for those scripts
├── assets/                               an index of files too big for git
├── claude-config/                        Claude's memory and settings, synced
└── <your projects>/                      each its own private repo
```

- Every project on GitHub, **private by default** — code, notes, or research
  alike
- Claude remembers each project across sessions and across machines
- Your task lists follow you, and each session leaves a short digest of what it did
- A second computer stays current on its own; when it can't, it says so
- **Silence means everything is fine.** The setup only speaks when something
  needs you
- A clear path to publishing something later, safely, if you ever want to

## What this is not

- Not a way to share work with a team — single person, one or more machines
- Not a backup for big binary files. Video, ROMs and build output stay local;
  the setup tracks a *list* of them so you know what's where
- Not automatic for your code. You still decide what to commit and when
- Not a git tutorial. It teaches the parts this workflow needs, not all of git
- Not only for programming. Writing, research and reading notes belong here too,
  and the setup does not care which a folder holds

It is also not a standard. This is one person's working setup, generalized far
enough to hand to someone else — the parts that are opinionated are opinionated
because they had to be decided somehow, not because the alternatives are wrong.
Change what doesn't suit you.

## Licence

Two licences, because this holds two different kinds of thing:

| What | Licence |
|---|---|
| The documents — every `.md` file here | **CC BY-SA 4.0** (`LICENSE`) |
| The scripts — everything in `templates/` | **MIT** (`LICENSE-CODE`) |

The scripts are MIT so you can copy them into your own workspace, change them,
and license the result however you like. The documents are BY-SA so that a
course or handbook built out of them stays as open as this is — which does not
mean handing them out next to your own notes puts your notes under BY-SA.

`COPYING.md` explains both, and what ShareAlike does and doesn't require.
