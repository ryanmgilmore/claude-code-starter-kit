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
Confirm it works standalone before wiring anything together:

```sh
codex --version
```

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

If it fails, the cause is almost always one of three things: `codex` isn't on
your PATH for the shell Claude Code launched from, you aren't logged in, or your
Codex CLI predates `mcp-server`. Run `codex --version` and `codex` on its own to
isolate which.

> **WSL2 users:** install Codex CLI *inside* Ubuntu, alongside Claude Code. The
> same one-side rule from `04-ENVIRONMENT.md` applies — a Windows-side Codex
> can't be reached by a Linux-side Claude Code.

---

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

`claude-config` syncs your MCP configuration along with everything else, so
registering Codex once makes it available on your other machine too — assuming
Codex CLI is installed there and logged in. `bootstrap.sh` doesn't install it;
that's a per-machine step, like Claude Code itself.

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
- Register once: `claude mcp add --transport stdio --scope user codex -- codex mcp-server`
- Ask it to critique, not to duplicate
- Delegation costs context — spend it where a second perspective actually pays
- You're still the manager. Two engineers is a bigger management job, not a
  smaller one

---

Back to **`06-DAILY-USE.md`**, which is where the habits that matter actually
live.
