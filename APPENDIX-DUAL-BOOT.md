# Appendix — running WSL2 and native Linux together

Reference material for one specific situation. **Most readers never need this**,
and nothing else in the kit depends on it. Come here only if you're already using
WSL2 and are considering installing real Linux alongside it.

The short version, if you want to stop reading now: *use git, not a shared
partition.* The rest explains why, and what to do in the case where sharing is
actually justified.

Prerequisites: `04-ENVIRONMENT.md`, and `01-WORKING-WITH-AN-AGENT.md` for why
absolute paths matter.

---

## The question

You're using WSL2 daily, you like it, and you're curious enough about a real
Linux system to install one — but you don't want two separate copies of your work
drifting apart.

The instinct is to make them share a home directory: one set of files, two ways
in. It's a good instinct, and it's mostly a trap. Here's the whole picture, since
this is the question people actually ask, and the answers online usually describe
one person's setup on the day it worked.

## First, the hardware question that decides everything

WSL2 can mount a real Linux partition. The command exists and works:

```powershell
wsl --mount \\.\PHYSICALDRIVE1 --partition 2 --type ext4
```

But **WSL2 cannot mount a disk that Windows is currently using — which includes
the Windows boot disk.** If Windows and Linux share one physical drive, as they
do on almost every laptop, this is unsupported and there is no flag that fixes
it. `wsl --mount` also attaches the *entire physical disk* even when you name a
single partition, which is why "just the Linux partition on my only SSD" isn't a
thing you can ask for.

So:

| Your hardware | Can WSL2 see your native Linux files? |
|---|---|
| One physical disk, partitioned (most laptops) | **No.** Not possible today |
| Two physical disks — Linux entirely on the second | **Yes**, with setup |
| Desktop with a spare drive, or a laptop with a free M.2 slot | **Yes**, with setup |

If you're on a single-disk laptop, the rest of this section is theory. Skip to
"What to do instead," which is what you want anyway.

## Why sharing `$HOME` is the wrong goal even when it's possible

Say you have two disks and it *is* possible. I'd still tell you not to share the
home directory, because `$HOME` is not a folder of your files. It's your files
**plus** `~/.config`, `~/.local`, `~/.cache`, and every dotfile you've ever
accumulated — and all of that describes *one specific system*.

The two systems are not the same system:

- **Different distributions**, or at least different versions, with different
  package layouts
- **Different kernels.** WSL2 runs Microsoft's kernel, not your distro's
- **One has a graphical desktop and one does not.** Your native install has a
  display server, a desktop environment, GUI application settings, keyring and
  session state. WSL2 has none of that, and will happily read those configs anyway
- **Different binaries at different versions**, sharing caches and compiled
  artifacts that were built against something else

Nothing announces the mismatch. It works, and then one day an application behaves
strangely in one environment because it's reading state written by the other, and
now you're debugging across two operating systems at once with no obvious reason
to suspect the boundary.

There's mechanical fragility on top of the conceptual problem:

- `wsl --mount` **requires an Administrator PowerShell**
- The mount **does not survive a reboot.** You'd script it through Task Scheduler
  and then depend on that script having run before you opened a terminal
- **Windows Fast Startup doesn't fully shut down.** Combined with hibernation,
  it's a well-known way to leave a filesystem in a dirty state that the other OS
  then refuses or, worse, doesn't refuse
- **UIDs must match.** Both default to 1000 so they usually do — check `id -u` in
  both — but if they don't, every file you touch has the wrong owner on the other
  side

## The version that *is* worth doing: share the projects, not the home

If you have the two disks and you want this, share `~/dev` and nothing else. Each
OS keeps its own home directory, its own dotfiles, its own configuration — and
your actual work lives in one place both can reach.

The design:

1. **Use the same username in both environments**, so `/home/yourname` exists in
   both
2. **Confirm the UIDs match** — `id -u` in each, expect `1000`
3. **Mount the shared partition at `/home/yourname/dev` in both.** A real
   mountpoint, not a symlink — you want the path to *be* that path, not to
   resolve to somewhere else
4. **Leave everything else alone.** Two `~/.config`s, two sets of installed
   packages, two shells configured independently

Why the mountpoint detail matters more than it looks: the payoff of this whole
arrangement is that `/home/yourname/dev/robot` is the **identical absolute path**
in both environments. That is exactly the key Claude Code files project memory
under — see `01-WORKING-WITH-AN-AGENT.md` — so getting it right means your
project memory survives a reboot into the other OS. Getting it wrong, via a
symlink that resolves elsewhere or a differing username, means memory silently
starts blank and nothing tells you why.

**Do not share `~/.claude` itself.** It holds settings and state tied to an
installation. Instead, use the mechanism this kit already gives you: treat native
Linux and WSL2 as **two machines**, and let the `claude-config` repo sync your
memory between them over git. That's precisely the problem it was built for, it
handles the conflict cases properly, and it doesn't care that your two machines
happen to be the same physical box. `07-SECOND-MACHINE.md` applies unchanged.

## What to do instead — and what I'd actually recommend

For nearly everyone reading this: **don't build any of it.**

Use git. Both environments clone from GitHub. `claude-config` syncs your memory
and task lists. `bootstrap.sh` reproduces your whole workspace on the Linux side
in one command, exactly as it would on a new laptop.

This is not a compromise version. Compared with the shared partition it:

- **Works on a single-disk laptop**, where the mount approach simply cannot
- **Works if you later add a real second machine**, which the partition trick
  does not
- **Fails safe.** A dirty filesystem or a missed mount can cost you files; a
  missed `git push` costs you one command
- **Requires no Administrator anything, no scheduled task, no reboot ritual**
- **Keeps the two systems honestly separate**, which they are

The cost is remembering to push before you reboot. That's it. And if you forget,
the session-start report on the other side tells you the moment you get there —
that's what it's for.

## Where a shared partition genuinely helps

One honest exception. Shared storage earns its place for **the things git should
never hold**: datasets, ROM dumps, sample libraries, video, model weights,
anything large and binary.

That material is already excluded from your repos (`06-DAILY-USE.md`, "The big
files that can't sync"), and the workspace tracks a *list* of it rather than the
bytes. A shared partition mounted somewhere like `/home/yourname/media` — with
each machine's `assets` inventory pointing at it — is a real, sane use of the
feature, and it carries none of the dotfile-collision risk because nothing in
there is configuration.

Share the bulk. Sync the code. Keep the configuration separate.

---

Back to **`04-ENVIRONMENT.md`**, or on to **`05-SETUP.md`** if you're done there.
