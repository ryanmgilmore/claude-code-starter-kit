# Working with an agent

Read this first. Everything in the rest of the kit — the memory syncing, the
handoff documents, the folder-per-idea habit — exists because of how agents
actually work. Once you know how they work, the rest stops looking like extra
steps for their own sake and starts looking like the obvious response.

You don't need to know any git to read this. `03-WHY.md` covers the tools —
what git and GitHub are, and what this setup adds around them — and it will make
more sense once you know what problem the agent has.

If you're a student and the question on your mind is whether using any of this
stops you learning, that's the right question and it gets a chapter of its own:
`02-LEARNING.md`, straight after this one. The short answer is that it can, that
the mechanism is specific, and that it's avoidable once you know what it is.

---

## The frame: you are the engineering manager

The most common way to misuse Claude Code is to treat it as a faster autocomplete
— ask for a function, get a function, paste it in, move on.

That works, and it wastes most of what you're holding.

A more useful frame: **you have hired an engineer.** A fast one, one that has
read an enormous amount of code, never gets bored, and works for cents an hour.
It also has no idea what you're building, no memory of last Tuesday, and no
judgement about which of your goals actually matter. It will do exactly what you
asked, including when what you asked was a bad idea.

That is a very specific kind of colleague, and there is a very specific way to
work with one. You do the things a manager does:

- **Say what you want and why**, not how to type it
- **Set constraints up front** — this must run on a Raspberry Pi, don't add
  dependencies, match the style of the existing code
- **Review the output** — read it, run it, push back on it
- **Decide the design questions yourself** — it will happily pick for you, and
  its pick is a coin flip weighted by what's common on the internet
- **Correct once, in writing, permanently** — see `CLAUDE.md` below

What you are *not* doing is proofreading its syntax. It's better at syntax than
you are. You're better than it is at knowing what this project is for.

### Where the analogy breaks

Take the metaphor seriously, but not literally. Three ways a real engineer is
different:

**It doesn't push back hard enough.** A human colleague who thinks your plan is
wrong will keep saying so. An agent mentions it once and then builds the thing.
If you want your ideas stress-tested, ask explicitly: *"before you build this,
tell me what's wrong with the approach."*

**It has no stake in the outcome.** It won't notice that the feature you asked
for makes the app worse, because it has never used the app.

**It forgets.** This is the big one, and the rest of this document is about it.

---

## What actually happens when you type

Worth understanding roughly, because every limit downstream comes from it.

When you send a message, Claude Code doesn't just answer. It runs a **loop**:

1. Read everything it currently knows — your message, the conversation so far,
   `CLAUDE.md`, whatever files it has opened
2. Decide on an action — usually *use a tool*: read a file, search the project,
   edit code, run a command
3. See the result of that action
4. Go back to 1, now knowing one more thing

It keeps looping until it decides it's done, then replies to you. A single
request like *"fix the failing test"* might be twenty of these steps: find the
test, run it, read the error, open the source file, read a related file, make an
edit, re-run, done.

That loop is what makes it an **agent** rather than a chatbot. A chatbot produces
text. An agent takes actions in the world, sees what happened, and adapts.

Two things follow immediately:

- **It can be wrong in ways a chatbot can't.** A chatbot gives you bad advice.
  An agent runs a bad command. This is why it asks permission before doing
  anything destructive, and why you should read what it's asking for rather than
  reflexively approving.
- **It gets better with more context, not more instructions.** An agent that can
  read your code doesn't need you to describe your code.

### Subagents — a team, briefly

Claude Code can spawn helpers: separate agents given one task, working in their
own space, reporting back a summary. Useful when a job needs a lot of searching
whose details you don't want cluttering the main conversation.

The catch: **a subagent starts cold.** It doesn't know anything the two of you
worked out over the last hour unless it's told. That makes it excellent for
"search the whole codebase and tell me where X is handled" and poor for anything
that depends on the shared understanding you've built up.

You don't usually need to manage this. Know it exists, so that when it happens
you know why.

---

## Tokens, and the context window

This is the part everything else depends on. Memory and handoff documents are
both answers to it.

### What a token is

Models don't read letters or words. They read **tokens** — chunks of roughly
four characters, or about ¾ of a word. `understanding` might be two tokens.
`}` is one. A page of prose is about 500. A medium source file is a few thousand.

Not important to count. Important to know they exist and that everything costs
some.

### The context window

The model can only consider a fixed amount at once — its **context window**.
Currently large: hundreds of thousands of tokens, a few hundred pages. Large,
but *fixed*.

Everything competes for that space:

- The system instructions that make Claude Code work
- Your `CLAUDE.md`
- Every message either of you has sent this session
- Every file it has read
- Every command it ran, **and all the output that command printed**

That last one surprises people. Run a test suite that prints 3,000 lines and
you've just spent a real fraction of the window on scrollback.

### What happens when it fills

Two things, in order.

**First, quality drops before space runs out.** A model with 200 pages in front
of it is genuinely worse at finding the important paragraph than one with 20.
Long sessions get vaguer, repeat themselves, forget constraints you set an hour
ago. If a session starts feeling stupid, it usually isn't the model having a bad
day — it's a full window.

**Then it compacts.** Claude Code summarizes the older parts of the conversation
and continues with the summary. Sessions don't crash; they *blur*. And a summary
is lossy in a specific, unlucky way: it keeps what looks like conclusions and
drops what looks like process — including the three approaches you tried and
rejected, and why.

### What to do about it

- **Start new sessions at natural boundaries.** Finished a feature? New session.
  A fresh window is faster and sharper than a tired one. This is the single
  highest-value habit in this document.
- **Don't paste what it can read.** Give it a path, not a file dump.
- **Write things down outside the conversation.** Which is the next section.

---

## Memory: what survives, and what doesn't

Close the terminal and the conversation is gone. Not archived, not "mostly
remembered" — gone. Tomorrow's session begins knowing nothing about today's,
except what got written to a file.

So the working question is never *"will it remember?"* It's **"where did that get
written down?"**

Three places, doing three different jobs:

| | What it holds | Who writes it |
|---|---|---|
| **`CLAUDE.md`** | Standing rules for this project, read at the start of every session | You (mostly) |
| **Memory files** | Facts learned over time — preferences, constraints, corrections | Claude |
| **`HANDOFF.md`** | The story of the project: what happened, what's next, why | Both |

### `CLAUDE.md` — standing orders

A file in the project root, loaded automatically every session. Nothing else in
this kit gives you as much for as little effort.

What belongs in it is what you'd tell a competent new hire on day one:

```markdown
## What this is
A MIDI librarian for the Yamaha QY-70. Python, no GUI.

## Build and run
`uv run qy70 --port 1`. Tests: `pytest`. There is no CI.

## Rules that must not be broken
- Never write to the device without a confirmation prompt
- No new dependencies without asking

## Mistakes not to repeat
- The device's sysex needs a 20ms inter-message delay. Without it,
  it silently drops messages. This has cost two afternoons.
```

The last section is the valuable one. Every time you catch the same mistake
twice, that's a line that should have been in `CLAUDE.md`. **Correct once, in
writing, permanently.**

Keep it short. It's read every session, which means it costs tokens every
session, which means a bloated `CLAUDE.md` makes every session slightly worse.

### Memory — what Claude writes down itself

Claude also keeps its own notes about a project between sessions, stored outside
the project folder in `~/.claude/`. Preferences you've expressed, constraints you
mentioned in passing, things it worked out the hard way.

The mechanical detail that matters: memory is filed **by the project's absolute
path** — the full location, like `/home/you/dev/robot`. Move or rename the
folder and the memory is orphaned; the project starts blank. Put the project at a
different path on a second computer and that computer sees a stranger.

This is why the rest of this kit is so insistent that every project lives at
`~/dev/<name>` on every machine you use. It isn't tidiness. It's the key the
memory is filed under.

### `HANDOFF.md` — the one you have to write yourself

`CLAUDE.md` says how the project works. `HANDOFF.md` says **where the project
is**: what was just done, what's half-finished, what was deliberately not done
and why, what you'd tell yourself if you came back in three months.

Nothing else captures that. Git history tells you what changed, not what you were
thinking. The conversation had it, and the conversation is gone.

It's most valuable at exactly the moments you're least inclined to write it — the
end of a long session, when you're tired and it all still feels obvious. It will
not feel obvious on Thursday.

The move that makes this painless: **end sessions by asking for it.**

> Update `HANDOFF.md` with what we did today, what's left, and the decisions we
> made and why.

It has the whole session in context right now. That's the last moment anyone
does.

A shape worth copying:

```markdown
# HANDOFF

## 1. Where this is
Sysex send works. Receive is written but untested against hardware.

## 2. Deliberately deferred, not forgotten
| Thing | Why not now |
|---|---|
| Bulk dump | Needs the receive path proven first |
| GUI | Wrong problem; CLI is fine |

## 3. Decisions
- **20ms inter-message delay.** Empirical, not from the manual. Device
  drops messages below ~15ms. Don't "optimize" this away.

## 4. Changelog (newest first)
### 2026-08-24
Receive path drafted. Untested — no hardware to hand.
```

Sections 2 and 3 are the ones that earn their keep. A list of things you chose
*not* to do, with reasons, stops you re-litigating them every month — and stops
an agent helpfully "fixing" a deliberate decision.

---

## Actually evaluating the work

You're the reviewer. The failure mode isn't the agent writing bad code; it's you
approving code you didn't read, twenty times, until the project is made of
material nobody understands.

A working minimum:

- **Read the diff.** Not every line of every file — the diff, the part that
  changed. If it's too big to read, it was too big to ask for in one go.
- **Run it.** "It compiles" is not "it works," and an agent that can't run your
  code is guessing about whether it works.
- **Ask it to explain anything you don't follow.** Free, instant, no ego. If the
  explanation doesn't land, that's a real signal — either it's wrong or the code
  is too clever.
- **Be suspicious of confident wrongness.** It will state a library's behaviour
  in the same tone whether it's certain or reconstructing from memory. For
  anything checkable — an API, a flag, a version — ask it to check rather than
  recall.
- **Keep tasks small enough to reject.** Rejecting an hour of work is easy.
  Rejecting a day of work is so unpleasant that people talk themselves into
  accepting it.

### Specify outcomes, not implementations

Weak: *"add a try/except around the file read."*

Strong: *"this should keep going if a file is unreadable, and tell the user
which one failed. There are three places that read files — handle them
consistently."*

The second gives it the actual goal, so it can notice the two places you forgot.
The first gets you exactly one try/except.

---

## Not only for building things

Everything above is written in terms of code, because that's the case with the
most moving parts. But an agent in a folder is just as useful before there is
anything to build, and this is the use people miss.

A folder with no code in it is a perfectly good project. Some things it can be:

- **A topic you're reading into.** Papers, links, and your own notes on them.
  Ask it to summarise what you've collected, find the disagreement between two
  sources, or tell you what you haven't looked at yet.
- **An idea you're still arguing with yourself about.** Talk at it for twenty
  minutes and ask for the argument written down — including the objections you
  couldn't answer.
- **A decision.** Which sensor, which framework, whether the project is worth
  doing. Ask for the case against your preference; it is much better at that
  than at telling you what to want.
- **Coursework that isn't programming.** A problem set you're stuck on, a report
  you're structuring, a lab you need to explain to yourself before you write it
  up.

The mechanics are identical. `CLAUDE.md` says what the topic is and what you
already believe. `HANDOFF.md` says where the thinking got to and what's still
open. Memory carries what you worked out. None of that cares whether the folder
contains source files or a pile of notes.

Two things change in how you work:

**The output is a document, not a diff.** So the review step becomes reading
what it wrote and disagreeing with it. Same discipline, different artefact — and
the same warning about confident wrongness applies with more force, because a
claim about a paper is harder to check than code that either runs or doesn't.
Ask it for sources and check them.

**Writing it down is the entire point**, where in a coding project it's the
supporting habit. A conversation that ends without a file is thinking you will
have to do again. End these sessions the way you end the others: *write down
what we concluded, what's still open, and what I should read next.*

The failure to avoid is the one people fall into with a chat window: a brilliant
half-hour that leaves nothing behind. The folder is what stops that.

### Why a terminal and a folder, rather than a notebook

The obvious objection: you can already write ideas down. Paper works, costs
nothing, and never needs configuring. Some of the best thinking anyone does
happens in a cheap notebook, and nothing here is an argument against one.

But a notebook and a workspace do different jobs, and it's worth being precise
about which parts are actually different — because "take notes on the computer
instead" is not the pitch, and if that were all this was, paper would win.

**It answers.** This is the whole of it, and everything else is a detail. Paper
is a place to put a thought. A folder with an agent in it is somewhere to *have*
one. You can say a half-formed idea out loud and get "what do you mean by
that?", or "that contradicts what you said ten minutes ago", or the name of the
thing you were groping towards. Rubber-duck debugging works because explaining
forces structure; this is that, except the duck knows things.

**It does the legwork while the thought is still warm.** Mid-sentence you wonder
whether the claim you just made is actually true. On paper that becomes a note
to check later, and later mostly doesn't come. Here it's a question you ask now
and an answer that lands inside the same twenty minutes — so the thought
continues from a fact instead of stopping at an assumption. Over a long session
that changes what you end up concluding, not just how fast you get there.

**Mess becomes structure without a second pass.** The gap between "I talked
about this for half an hour" and "I have a document about this" is where most
thinking dies — it's real work, and you're least willing to do it at exactly the
moment it's needed. *"Write up what we just worked out, list the open questions,
and say what I should read next"* closes that gap for free, while the whole
conversation is still in front of it.

**You can find it again.** `~/dev` is one searchable place. A `grep` across it
answers "where did I write about that?" in a second. Notebooks are, honestly,
write-only for most people: filled diligently, consulted almost never, and
impossible to search when you do try.

**It has a history.** Because each folder is a git repo, your thinking has a
timeline — you can see how a view changed and when, and read what you believed
before you changed your mind. That's a genuinely different object from a stack
of undated pages, and it's occasionally worth a lot: the reason you rejected an
approach in March is exactly what you need in June, and it's the first thing you
forget.

**It survives, and it follows you.** Backed up, on every machine you use. No
notebook left on a train has ever been recovered.

**It's already where the work happens.** An idea that turns real needs no
transcription — the folder becomes a repo, the notes become the README, the open
questions become the first issues. Paper has a copying step between thinking and
doing, and every copying step is somewhere a project stops.

### What paper is still better at

Being honest about this makes the rest more credible:

- **Drawing.** Diagrams, circuits, state machines, the shape of a thing. Sketch
  it, photograph it, drop the photo in the folder.
- **Thinking slowly.** Writing by hand is slow in a way that is sometimes the
  point. A terminal invites you to keep moving.
- **Not being agreed with.** A page never flatters you. An agent will take a
  vague thought and hand you back a fluent paragraph that *sounds* resolved —
  and reading your own half-idea in confident prose is a very easy way to
  believe you finished it. If you want the idea tested, you have to ask: *"what's
  wrong with this?"*, *"argue the other side"*, *"what am I assuming?"* It will
  do it well, and it will not do it unprompted.

The failure worth naming: letting it do the *formulating*. If the conclusion in
the file is one it wrote and you nodded at, you haven't had an idea, you've read
one. The division that works is you thinking and deciding, it questioning,
checking and capturing.

### The journal you get without keeping one

There's a side effect worth pointing out, because most people would never set it
up deliberately and it turns out to be the most valuable artefact in the
workspace.

Between the changelog at the bottom of each `HANDOFF.md`, the per-session
digests, and the commit history, every project accumulates a **dated record of
what you did and why** — written at the time, by someone who had the full
context, which is to say not by you three months later trying to remember.

Nobody sustains a journal by discipline. Everyone abandons one by February. This
one is a by-product of working, which is the only kind that survives — and it
answers, months later, the two questions that otherwise cost an afternoon each:
*what was I doing?* and *why did I do it that way?*

---

## The habit that costs nothing: a folder per idea

The practice the rest of this sits on, whether or not the idea is code.

**Every idea gets a folder in `~/dev`, immediately, at the moment you have it.**
Not when it's real. Not when you're sure. When you think of it.

Most of them go nowhere — a `README.md` with four lines and a dead end. That's
fine, and it's the point. The cost of a folder is nothing. The cost of an idea
you had in the shower in March and can't reconstruct in June is the idea.

What this buys you:

- **Thinking gets somewhere to live.** Open Claude in an empty folder and talk
  through an idea for twenty minutes. Ask it to write down what you concluded.
  Now it's a document instead of a mood.
- **You can find it again.** `~/dev` is one place. Not Notes, a text file on the
  Desktop, a Discord message to yourself, and a napkin.
- **Ideas that turn real are already in position.** Nothing to move. It's
  already a folder with notes; it becomes a repo when it deserves one.
- **You can see what you actually care about.** Six abandoned folders circling
  the same subject is information about you.

The tooling in this kit makes the cheap version cheap — `new-project.sh` gets you
a folder, a repo, and a backup in one command (see `06-DAILY-USE.md`). But the
habit works with `mkdir` and nothing else. Start with `mkdir`.

---

## The honest version

Things that are true and mostly get left out of the pitch:

- **It's a bad architect.** Give it a clear task in an existing structure and
  it's remarkable. Ask it to decide how a system should be shaped and you get
  something plausible, generic, and often wrong for you. That decision is yours.
- **It's confidently wrong at a steady rate.** Not often, but never with a change
  in tone. Verification is a permanent tax, not a beginner phase.
- **It rewards writing.** People who get the most out of this are people who
  write clear specifications — which was already true of working with humans.
- **Long sessions decay.** You'll relearn this personally about four times before
  it becomes a habit.
- **It doesn't remove the need to understand your project.** It removes the
  typing. If you don't understand what you're shipping, you have a codebase you
  can't debug and a very fast way to make it larger.

Used well, this is the difference between shipping one project a year and
shipping six — and between abandoning a project when you lose the thread and
picking it up two months later from a document that tells you exactly where you
were.

---

## The risks, in one place

Each of these is dealt with properly in the document where you'd act on it —
that's deliberate, because a warning is useful next to the thing it's warning
about and forgettable in a list. But a list is easier to check yourself against,
so here they all are.

| Risk | The short version | Covered in |
|---|---|---|
| The agent runs a destructive command | It asks first. The failure mode is approving without reading, which becomes tempting around the fiftieth prompt | This chapter, above |
| It's confidently wrong | At a low, steady rate, with no change in tone. Verification is permanent, not a beginner phase | This chapter, `02-LEARNING.md` |
| You stop learning the thing you're studying for | Real, specific, and avoidable — but only if you know the mechanism | `02-LEARNING.md` |
| A committed secret is permanent | Deleting it next commit doesn't remove it. Any committed key is a compromised key | `06-DAILY-USE.md` |
| Publishing exposes your whole history | Not just the current files. This is why you never flip a repo to public | `06-DAILY-USE.md` |
| You put someone else's material into it | It reaches GitHub and the model. That's your call to make about your own work, and not about theirs | `06-DAILY-USE.md` |
| Work lost between two machines | Edit both without pushing and git refuses to merge. The setup stops rather than guessing | `07-SECOND-MACHINE.md` |
| It costs money | Claude Code needs a paid plan. Check what your university provides first | `05-SETUP.md` |

Two that don't fit the table, because they aren't events you can guard against
so much as conditions to notice:

- **Nothing here is a backup of your judgement.** The setup makes your work
  durable, findable and portable. It has no opinion about whether the work is
  any good, and neither does the agent — it will help you build the wrong thing
  as efficiently as the right one.
- **Nothing here is a backup, full stop.** GitHub holds your repos, and that is
  genuinely most of the way there. It does not hold the large files the inventory
  merely lists, and it is one account you can lose access to. If something would
  actually hurt to lose, it needs a copy that isn't downstream of a single login.

---

Next: **`02-LEARNING.md`** — whether leaning on any of this costs you the thing
you're studying for.
