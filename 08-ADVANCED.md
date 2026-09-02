# Advanced — more than one agent

Optional. Nothing else in this kit depends on it, and you should not read it
until the rest is habit.

Prerequisites: you've set the workspace up, you commit without thinking about it,
and `01-WORKING-WITH-AN-AGENT.md` describes how you already work rather than
something you read once.

---

## Why this document exists

Claude Code needs a paid plan. Many universities separately provide students with
access to **OpenAI Codex** — through a ChatGPT Edu licence, a departmental
account, or a research allocation.

If that's you, you have a second coding agent sitting there already paid for.
This document is about using it *from inside* Claude Code rather than as a
separate window you alt-tab to.

Two honest framings before anything technical:

**This is not a free upgrade.** You are adding a second engineer to a team you
manage. That's a delegation problem, and delegation has overhead. If you don't
yet have a feel for supervising one agent, adding a second makes your work worse,
not better.

**You do not need this.** One agent, used well, is more than most people ever get
out of these tools. This is for the case where you have capacity you've already
paid for and want it doing something useful.

---

## The idea

Both Claude Code and Codex CLI speak **MCP** — the Model Context Protocol, a
common language that lets one program expose tools to another over a plain
stdio channel.

Codex CLI can run *as* an MCP server. That means Claude Code can treat Codex the
way it treats any other tool: hand it a task, get a result back. You stay in one
terminal, one conversation, one project.

Structurally it's the subagent pattern from `01-WORKING-WITH-AN-AGENT.md`, with
one difference that matters: the delegate is a different model from a different
company, with different training and different failure modes. That's the actual
value — not more capacity, but a **second opinion that isn't correlated with the
first**.

---

## Setup

### 1. Install Codex CLI

Follow OpenAI's current instructions at <https://developers.openai.com/codex>.
On macOS, Homebrew has it:

```sh
brew install codex
codex --version
```

Confirm it works standalone before wiring anything together.

You need the current Rust-based Codex CLI — the `mcp-server` mode below doesn't
exist in the older builds.

### 2. Log in with your institutional account

Run `codex` and authenticate. If your university provides access, use that
account rather than a personal one — and check your institution's policy on what
may be sent to it. Coursework usually fine; anything under NDA from an internship
usually not. That's a real question, not a formality.

### 3. Register Codex with Claude Code

```sh
claude mcp add --transport stdio --scope user codex -- codex mcp-server
```

`--scope user` makes it available in every project. Use `--scope project` to
limit it to one — worth doing if only some of your work should touch a second
vendor.

Equivalently, by hand in `~/.claude.json`:

```json
{
  "mcpServers": {
    "codex": {
      "type": "stdio",
      "command": "codex",
      "args": ["mcp-server"]
    }
  }
}
```

### 4. Check it

```sh
claude mcp list
```

Codex should appear and report as connected. Inside a session, `/mcp` shows what
tools are actually available.

**"Connected" does not mean "working."** The MCP server starts fine whether or
not you are logged in — it is the tool *calls* that would fail. Check the login
separately, and prove the whole path end to end before trusting it:

```sh
codex login status
codex exec --skip-git-repo-check "Reply with exactly: codex ok"
```

Also note that a session already running when you registered the server will not
see it. Restart Claude Code, then check `/mcp`.

If it fails, the cause is almost always one of three things: `codex` isn't on
your PATH for the shell Claude Code launched from, you aren't logged in, or your
Codex CLI predates `mcp-server`. Run `codex --version` and `codex` on its own to
isolate which.

> **WSL2 users:** install Codex CLI *inside* Ubuntu, alongside Claude Code. The
> same one-side rule from `04-ENVIRONMENT.md` applies — a Windows-side Codex
> can't be reached by a Linux-side Claude Code.

---

## How you actually invoke it

There is no mode to switch into and no flag. You ask, in a normal sentence, and
Claude calls the tool:

> Ask Codex whether this refill logic drops a frame when the buffer wraps.
> Get a second opinion from Codex on `src/transfer.rs` before we commit.

The registration exposes exactly two tools — `codex`, which starts a session,
and `codex-reply`, which continues one. The `codex` tool takes a `prompt`, a
`cwd`, an optional `model`, and a `sandbox` of `read-only`, `workspace-write`
or `danger-full-access`. **For review work, insist on `read-only`.** There is no
reason to let a second vendor's agent write to your tree, and it removes the
"both agents edited the same files" failure listed below by construction.

### The thing that decides whether this is useful

**Codex starts cold.** It does not see your conversation with Claude, your
`CLAUDE.md`, or the decision you made four messages ago. It gets one prompt.

So the prompt has to stand alone — the file path, the actual question, the
constraint that matters:

> In `src/transfer.rs`, `send_chunk` assumes the device ACKs within 50ms. Does
> anything in this file mishandle a late ACK that arrives after a retry was
> already sent? Read-only; don't propose refactors.

Ask for "a review of this" instead and you get generic lint-flavoured output,
because generic is all a cold model can produce from a vague prompt. This is the
single most common reason people set Codex up, try it twice, and never use it
again. It reads as "the second agent isn't very good." It is actually "the
second agent was told nothing."

Tell Claude to send self-contained prompts, and to report both what Codex said
*and* whether it agrees. A second opinion you adopt automatically is not a
second opinion.

## Using it well

The default failure is asking for the same work twice and having no way to
choose between two confident answers. Give the second agent a **different job**,
not the same job again.

Four that genuinely work:

**Adversarial review.** The highest-value use by a distance.

> Ask Codex to review the change we just made, specifically looking for
> correctness bugs and edge cases we've missed.

You get a critique from a model that didn't write the code and has no investment
in the approach. Independent review is exactly what a lone student developer
otherwise has no access to.

**Second opinion on a design decision.** Before you commit to a structure, ask
both and read the disagreement. Where they agree, you're probably on safe ground.
Where they differ, you've found the part that's genuinely a judgement call — and
that's the part you should be deciding yourself.

**Parallel search on a big unfamiliar codebase.** Two agents reading different
parts of a large project and reporting back is real time saved, especially in a
codebase neither you nor Claude has seen before.

**A sanity check on something confidently stated.** When Claude asserts an API
behaviour or a library detail with more confidence than the situation warrants,
a second model is a cheap check. Not proof — both can be wrong the same way —
but two independent wrongs are rarer than one.

### Making it a habit, which is the hard part

Setting this up takes ten minutes. Actually using it is the part that fails —
it is entirely normal to be logged in for weeks and never once reach for it.

The reason is that "get a second opinion" is a vague virtue, and vague virtues
lose to momentum every time. You are mid-task, you have an answer in front of
you, and stopping to consult a second agent feels like a detour. It never wins
that argument on the day.

The fix is to stop making it a judgement call. Name the triggers in advance, in
a file the agent reads every session, so it fires as a rule:

1. **Before a commit touching a path that has burned you before.** Name the
   paths in the project's handoff notes. Not "important code" — actual paths.
2. **When Claude has already been wrong once in this session.** It contradicted
   itself, or a fix didn't work. This is the highest-value moment and the one
   you will never think of unprompted.
3. **When you disagree with Claude and don't have time to adjudicate.** A third
   position breaks a tie better than the same agent restating its own.
4. **Reading unfamiliar upstream code.** Low stakes, and it calibrates you on
   whether Codex is any good at your kind of problem before you rely on it.

Not worth the hop: anything a test would settle faster, style questions, and
anything where you would happily accept either answer.

Putting that in your global `CLAUDE.md` is what turns it from an intention into
behaviour:

```markdown
## Second opinion (Codex)

Codex CLI is registered as an MCP server. Reach for it when: you have already
been wrong once this session, I disagree with you and don't want to adjudicate,
or a commit touches a path the project's handoff notes call fragile.

Codex starts cold — it sees nothing of our conversation. Send self-contained
prompts: file path, the specific question, the constraint. Default to
`sandbox: read-only`. Report what it said *and* whether you agree; never adopt
its answer just because it is a second voice.
```

### What not to do

- **Don't have both edit the same files in the same session.** You will get
  conflicting changes with no clear history of which agent did what, and
  reviewing that is worse than doing the work yourself.
- **Don't delegate to avoid understanding something.** Two explanations you
  didn't read is not better than one you did.
- **Don't route everything through Codex because it's free.** Every hop costs
  context and time. Delegate when the second perspective is the point.
- **Don't let it turn into two conversations you're managing.** You're the
  manager. Two direct reports is a workload; four is a meeting.

---

## The cost nobody mentions

Delegation spends **context** — the resource `01-WORKING-WITH-AN-AGENT.md`
identifies as the one you're really managing.

Every call sends a task description out and brings a summary back, and both live
in your session window. Three or four delegations into a long session, you've
spent real space on coordination rather than work. The session gets vaguer
earlier, and you compact sooner.

Which produces the rule that actually governs this:

**Delegate for a genuinely different perspective. Don't delegate to save
yourself typing.**

If the answer would be roughly the same either way, asking twice costs you
context and buys you nothing.

---

## Where this sits in the setup

Registering Codex is a **per-machine step**, and so is installing the CLI.
`claude mcp add --scope user` writes to `~/.claude.json`, which `claude-config`
deliberately does not sync — that file also holds session state that is
meaningless on the other machine. `bootstrap.sh` doesn't install Codex either.
So on the second machine you run all of steps 1-4 again.

A `--scope project` registration is different: it lands in the project's
`.mcp.json`, which is in the repo, so that one does travel.

If you write anything project-specific about when to use the second agent, it
belongs in that project's `CLAUDE.md` under a rule Claude reads every session:

```markdown
## Second opinions
Before any change to the sysex timing code, have Codex review it. That path has
cost us two afternoons and the failure is silent.
```

That way the delegation happens because the project needs it, not because you
remembered.

---

## The short version

- Use it if you already have institutional Codex access; don't buy it for this
- The value is **independent review**, not extra throughput
- Register per machine: `claude mcp add --transport stdio --scope user codex -- codex mcp-server`
- Invoke it by asking in plain language; use `sandbox: read-only` for review
- **Codex starts cold** — self-contained prompts, or the answers are worthless
- Ask it to critique, not to duplicate
- Name the triggers in your `CLAUDE.md`, or you will never actually use it
- Delegation costs context — spend it where a second perspective actually pays
- You're still the manager. Two engineers is a bigger management job, not a
  smaller one

---

Back to **`06-DAILY-USE.md`**, which is where the habits that matter actually
live.
