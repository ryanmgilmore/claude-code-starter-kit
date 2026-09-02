# Choosing your environment

Read this third. If you're on a Mac, skim it and move on — you're already done,
and section 1 is still worth five minutes.

If you're on Windows, this is a real decision with four options, and the one
most guides push at you is not the one this kit recommends. The reasoning
matters more than the recommendation, so it's laid out rather than asserted.

---

## 1. First, an honest correction

You may have heard that Claude Code requires Linux, or requires WSL. **That
hasn't been true since late 2025.** There is a native Windows installer. One
PowerShell command, no Node.js, no Linux, auto-updating. It works.

So the question is not *"can I run this on Windows?"* You can. The question is
whether you *should*, and that's a genuine trade rather than a formality.

Anyone telling you Windows simply doesn't work is repeating something that
expired. Anyone telling you the native installer makes the question go away is
skipping the parts of this document that follow.

---

## 2. Why anyone runs coding agents on Unix

Set Claude Code aside for a second. The reason to care about Unix — macOS,
Linux, or Linux-inside-Windows — is that **the agent's real power is running
commands, and almost every command it knows is a Unix command.**

Think back to the agent loop in `01-WORKING-WITH-AN-AGENT.md`. The agent's
usefulness scales with what it can *do*, not what it can say. What it does is
run things: `grep`, `find`, `sed`, `curl`, `make`, `git`, small shell pipelines
it composes on the spot. That vocabulary is fifty years deep, and it's the
vocabulary the model has read the most of, by an enormous margin.

Four practical consequences:

**Its instincts fit the environment.** Ask it to find every file mentioning a
function and it reaches for a shell pipeline. On Unix that works first try. On
PowerShell it works, but it's operating in its second language — more retries,
more corrections, more of the loop spent on the tool instead of your problem.

**Instructions you find will fit.** Every README, every Stack Overflow answer,
every install guide for developer software assumes a Unix shell. On Windows you
are permanently translating. So is the agent.

**Servers are Linux.** If anything you build ever gets deployed — a web app, an
API, a script on a Raspberry Pi — it runs on Linux. Developing on Linux means
the thing that worked on your machine works there too. This is the single most
common source of "but it worked locally."

**The sandbox is Unix-only.** Claude Code can run commands inside a sandbox that
limits what they can touch — genuinely valuable when you're letting an agent run
commands you haven't fully read. As of now that feature requires WSL2 or a real
Unix system. On native Windows you don't get it.

None of this makes Windows unusable. It makes Windows a place where you spend a
fraction of your attention on friction that Unix users don't have. Over a
semester that fraction adds up.

**Also relevant to this kit specifically:** the tooling in `templates/` is bash
scripts. On native Windows they don't run without a translation layer.

### What you get out of this, separate from the agent

Everything above is about what the *agent* gains. There's a second argument, and
over a few years it's the bigger one.

**You will learn the terminal without ever sitting down to learn the terminal.**

This is a genuinely unusual on-ramp. Normally the shell is miserable to pick up:
a wall of two-letter commands, no discoverability, error messages written for
people who already know. Learning it alongside an agent inverts that. Every
command that runs has a reason attached, and there is something sitting next to
you that will explain any of it, at any level of detail, without making you feel
slow for asking. *"What did that command just do?"* is free, instant, and
unembarrassing.

Six months of working this way and you have real shell fluency you never
scheduled. That skill outlives Claude Code. It outlives whatever replaces Claude
Code. `ssh`, `grep`, pipes, permissions, processes, `git` at the command line —
this is the substrate every developer job sits on, and "I've used an AI coding
tool" is not a substitute for it in a way anyone hiring can see.

There's a second effect that matters more than it sounds: **the terminal is where
you can watch the agent work.** A graphical tool hides the commands behind
buttons. A terminal shows you every single one before and as it runs. Reading
what it actually did — not what it said it did — is how the manager frame from
`01-WORKING-WITH-AN-AGENT.md` turns into a habit instead of a slogan. You cannot
supervise what you cannot see.

So the Unix argument isn't only "the agent works better there." It's that the
environment where the agent works best is also the environment where *you* learn
most, and where you can actually see what's being done in your name.

---

## 3. The four options

### Option A — Native Windows

Install Claude Code directly on Windows. PowerShell, no Linux anywhere.

**Requirements:** Windows 10 version 1809 or later, 4 GB RAM, x64 or ARM64.

| Good | Bad |
|---|---|
| Easiest possible start — one command, minutes | No sandbox support |
| No new concepts: one filesystem, one OS | Agent works in its second-best shell |
| Full speed, no virtualization overhead | Instructions you find need translating |
| Windows apps and files right there | This kit's bash tooling doesn't run |
| Auto-updates | Line-ending and path-separator papercuts |

**Choose this if:** you're building Windows things (C#, .NET, Unity, Windows
games), or you want to try Claude Code in the next ten minutes with zero setup.
It is a completely legitimate choice, and it is much better than not starting.

### Option B — WSL2 *(the recommendation)*

Windows Subsystem for Linux: a real Linux kernel running alongside Windows, in a
window. Not an emulator, not quite a VM — Microsoft builds it, ships it, and
supports it as part of Windows.

**Requirements:** Windows 10 version 2004 (build 19041) or higher, or any
Windows 11.

| Good | Bad |
|---|---|
| Real Linux — real bash, real package manager, real everything | One concept to learn: two filesystems, and which one to use |
| Sandbox support | Crossing between them is slow, so you keep code on the Linux side |
| Windows and Linux at once — VS Code bridges cleanly | GUI Linux apps work, but that's not what it's for |
| Instructions you find just work | Some RAM overhead |
| No reboot, no partition, no commitment | |
| Uninstall is one command if you hate it | |

The failure mode worth naming now, because it's the one everybody hits: **keep
your projects inside the Linux filesystem** (`~/dev`), not on the Windows drive
(`/mnt/c/...`). Files on the Windows side are reachable, but every read crosses a
boundary, and a project living there is dramatically slower — slow enough that
people conclude WSL is bad, when they've actually just put their code in the
wrong place. `~/dev` on the Linux side, always. Reach it from Windows via the
`\\wsl$` share when you need Explorer.

### Option C — A Linux virtual machine

Full Linux inside a window, via VirtualBox, VMware, or similar.

| Good | Bad |
|---|---|
| Genuinely, completely Linux | Slower than WSL2 for the same work |
| Fully isolated — break it, delete it, remake it | You allocate RAM and disk up front, and it's walled off |
| Snapshot before something risky | Sharing files with Windows is clumsier than WSL2 |
| Practise a whole system safely | Another OS to update and maintain |

**Choose this if:** you specifically want to learn Linux administration as a
subject, or you need a system you can snapshot and destroy. For everyday
development on Windows, WSL2 does the same job with less friction.

### Option D — Dual-boot

Linux installed on the disk properly, choose your OS at power-on.

| Good | Bad |
|---|---|
| Full hardware speed, full GPU | **You can only use one at a time** |
| A genuine, complete Linux machine | Repartitioning risks your data if it goes wrong |
| Nothing is emulated or bridged | Hardware may need work — Wi-Fi, sleep, battery |
| Best way to actually learn Linux | Reboot to open a Windows app |
| | Your files are split across two worlds |

That first "bad" item is decisive and gets underestimated. It isn't only about
files: your entire working state — every open terminal, every running session,
every half-finished thought — lives in the OS you are not currently booted into. Not "mildly
inconvenient" — you are mid-task, you need a Windows-only application for one
thing, and the cost is closing everything and rebooting. In practice most
dual-booters stop booting the second OS within a month, and it's usually Linux
that loses, because coursework is on the Windows side.

**Choose this if:** you want Linux for its own sake, you have a spare machine or
a second drive, and you already know you'll live in it. Do not choose this
because you think it's the "serious" option for running an agent. It isn't — it's
the option with the highest cost and the least relevance to the actual work.

**If you do it anyway:** back up first, install Windows before Linux, use a
separate physical drive if you have one, and expect an afternoon.

### Option E — Switch to Linux entirely

| Good | Bad |
|---|---|
| No friction, no boundary, no translation | Some coursework software is Windows-only |
| Fast, private, yours | MS Office and Adobe don't run properly |
| Everything a developer needs is native | Some hardware fights you |
| Free | Games are much better than they were, still not equal |

**Choose this if:** you've checked what your degree actually requires and it's
all browser-based or cross-platform. Check before, not after. One required
Windows-only application for one module is enough to make this painful.

---

## 4. So: which one

**Windows, and you're here to build software → WSL2.**

The argument in one line: it's the only option that gives you real Linux, real
bash, sandbox support, and this kit's tooling, **without asking you to give up
anything** — no reboot, no partition, no lost access to Windows, and one command
to remove it.

Every other option trades something real away:

- Native Windows trades the sandbox, the tooling, and the agent's best shell —
  in exchange for saving twenty minutes once
- A VM trades speed and convenience for isolation you probably don't need
- Dual-boot trades *using both operating systems at the same time*, which is the
  largest price on this page
- Switching entirely trades your ability to run Windows software at all

WSL2's only real cost is one concept — two filesystems, keep your code on the
Linux side. That's a paragraph of learning against everything else on this list.

**The honest exceptions:**

| You're... | Use |
|---|---|
| Building .NET, Unity, or Windows desktop apps | Native Windows |
| Wanting to try this in ten minutes with no reading | Native Windows — move to WSL2 later, nothing is lost |
| On Windows 10 older than build 19041 and can't update | Native Windows or a VM |
| Learning Linux administration as a goal in itself | A VM |
| Doing GPU work — local models, CUDA training | Dual-boot or native Linux |
| Already on a Mac | Nothing. You have Unix. Continue |

**And the meta-point:** you can change your mind. Native Windows today and WSL2
in October costs you nothing, because your code lives on GitHub (that's the whole
point of `03-WHY.md`) and this setup rebuilds from a manifest on any machine.
Pick something and start. The worst option is the one where you spend three
weeks researching operating systems instead of building the thing you wanted to
build.

---

## 5. If you chose WSL2 — the ten-minute version

Full detail is in `05-SETUP.md`; this is just enough to know what you're in for.

Open PowerShell **as Administrator**:

```powershell
wsl --install
```

That installs WSL2 and Ubuntu. Reboot when it asks. On the way back up it asks
for a Linux username and password — **use the same username you use on your other
machines** if you have any, for the reason in `01-WORKING-WITH-AN-AGENT.md`
(memory is filed under the project's absolute path, and your username is in that
path).

You now have "Ubuntu" in the Start menu. That's your terminal. From here on,
whenever this kit or any other guide says "open a terminal," it means that one —
not PowerShell, not Command Prompt.

Two rules that save you the common misery:

1. **Your projects live in `~/dev` on the Linux side.** Never in `/mnt/c/`.
2. **Install developer tools inside Ubuntu**, not on Windows. Git, Node, Python,
   Claude Code — all of it goes in the Linux side, with `apt` or the standard
   installer. Two copies of a tool in two places is how you spend an evening
   confused about which one you're running.

> ### The trap: don't install Claude Code twice
>
> It is entirely possible to install Claude Code on Windows **and** inside WSL2.
> Nothing stops you, nothing warns you, and it will quietly waste an evening.
>
> They are two separate programs. Two binaries, two `~/.claude` directories, two
> unrelated sets of project memory — and because memory is filed by the project's
> absolute path, the Windows one files your work under `C:\Users\you\...` while
> the Linux one uses `/home/you/dev/...`. Different keys, different worlds.
>
> The symptom is baffling: you open a project you worked on yesterday and Claude
> has never heard of it. Nothing is broken and nothing tells you why.
>
> **Pick one side and stay there.** For this kit, that side is WSL2. If you
> already installed the Windows version while trying things out, uninstall it
> before going further:
>
> ```powershell
> Remove-Item -Path "$env:USERPROFILE\.local\bin\claude.exe" -Force
> ```
>
> The same logic is why the path rules in this kit are strict rather than fussy.

To open your project in VS Code from the Ubuntu terminal:

```sh
code .
```

The first time, it installs a small helper automatically. After that, VS Code
runs on Windows, looks native, and edits files on the Linux side with a full
Linux terminal built in. This is the setup that makes the whole thing feel like
one machine instead of two.

Continue to `05-SETUP.md`, and follow the Linux path wherever it branches.

---

## 6. "What if I want WSL2 *and* real Linux?"

A reasonable place to end up: you're using WSL2 daily, you like it, and you're
curious enough about a real Linux system to install one — but you don't want two
copies of your work drifting apart.

**The short answer: use git, not a shared partition.** Both environments clone
from GitHub, and `claude-config` syncs your memory between them. Treat native
Linux and WSL2 as two machines and `07-SECOND-MACHINE.md` applies unchanged — it
does not care that your two machines are the same physical box.

The tempting alternative — one home directory shared between both — is mostly a
trap, and on most laptops it isn't even possible: WSL2 cannot mount a disk that
Windows is using, which includes the Windows boot disk. If Windows and Linux
share one drive, there is no way to do it.

Full detail — the hardware constraint, why `$HOME` is the wrong thing to share,
the one arrangement that *is* worth doing, and the case where a shared partition
genuinely earns its place — is in **`APPENDIX-DUAL-BOOT.md`**. It's reference
material; you don't need it to set anything up.

---

Next: **`05-SETUP.md`** — building the workspace from zero.
