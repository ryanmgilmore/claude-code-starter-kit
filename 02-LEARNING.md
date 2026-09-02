# Does this stop you learning?

If you're a student, this is the question that actually matters, and it deserves
a straight answer rather than reassurance. It's also the one this kit would be
dishonest to skip, since everything else in it is written to make using an agent
easier.

Read it after `01-WORKING-WITH-AN-AGENT.md` — the answer depends on the
reviewing discipline that chapter describes.

**Yes, it can. Easily. And the way it happens is worth understanding, because it
is avoidable and it is not obvious while it's happening.**

## The mechanism

You learn to program by being stuck and then getting unstuck. The struggle is
not an unfortunate side effect of learning — it substantially *is* the learning.
Sitting with a segfault for an hour is how you build the instinct that later
tells you, in four seconds, that it's a null pointer.

An agent removes the struggle. That's the entire pitch. Which means it also
removes the mechanism.

Worse, reading a correct solution *feels like* understanding. It's fluent, it
makes sense line by line, you nod along. That feeling is not the same as being
able to produce it, and the gap between the two is invisible from the inside
until an exam or a broken build makes it visible. This is the specific trap: not
that you'll knowingly cheat yourself, but that you'll genuinely believe you
learned something you only watched.

## The distinction that resolves it

Not all work you do is learning work. Two different activities get confused:

| | The point is | The code is |
|---|---|---|
| **Acquiring a skill** | That *you* can do it afterwards | Practice — the output is disposable |
| **Applying a skill** | That the thing exists and works | The product |

Writing your fourth linked list is acquiring. Wiring up a config parser for a
robotics project is applying. The same keystrokes, completely different purpose —
and the agent is right for one and corrosive to the other.

Nobody can tell them apart for you. But you always know, before you start, which
one you're doing. The discipline is to decide *then*, not at the moment the task
turns unpleasant — because that moment is exactly when it stops being a decision
and starts being an excuse.

Plenty of real work is both at once — that's what design projects are, and they
get their own section below. The split is still the right thing to reach for
first, because most single tasks land clearly in one column even when the
project doesn't.

## Using it without hollowing yourself out

When you're **applying** a skill you have, delegate freely. That's the rest of
this document.

When you're **acquiring** one, the agent is still useful — as a tutor, not an
author. The difference is what you ask for:

- **Ask for a hint, not the answer.** *"I'm stuck on why this segfaults — ask me
  questions until I find it"* rather than *"fix this."*
- **Write it yourself, then have it reviewed.** You get the struggle and the
  correction. This is better than either doing it alone or having it done.
- **Ask it to explain the thing you just wrote**, and check whether its
  explanation matches your reasons. Where they differ, one of you is wrong and
  it's worth finding out which.
- **Have it set you problems**, then don't let it near the answers.
- **Ask why an approach is wrong**, which is the part textbooks skip and the part
  that transfers.

## The rule, in the right currency

The obvious rule is *don't accept code you couldn't have written yourself*. It's
close, and it's measuring the wrong thing.

It measures what you can **produce**. What actually has to hold is what you can
**follow** — and those come apart in the case that matters most. Code a step past
what you could have produced, that you understand completely once you read it, is
not a loss. It's the ordinary way anyone learns anything: you work a little
beyond your current reach with support, and the reach moves. A rule that confines
you to what you could already have written keeps you out of exactly the zone
where learning happens.

So the rule is about comprehension:

> **Don't accept code you can't follow.** Not "couldn't have written" —
> can't *follow*: can't explain what it does, can't predict what breaks if you
> change it, can't tell when it's lying to you.

With the warning from earlier attached, because it's the whole difficulty:
following code *feels* automatic when you read it. Test it rather than trusting
the feeling. "I understand this" is weak evidence. "I can modify this and predict
what that breaks" is strong evidence, and it takes about a minute to check.

Past that line you've stopped being the reviewer, and everything in this document
depends on you being the reviewer.

## When it's fine to take code you couldn't have produced

Outside coursework, accepting code you couldn't have produced yourself is
sometimes exactly the correct call. A build script in a language you don't work
in. Glue against an API you'll touch once. The tricky part of a library you have
no intention of becoming an expert in. Every working engineer does this
constantly — it's most of what using a library *is* — and refusing on principle
would mean doing nothing but reimplementing solved problems.

What makes it legitimate there is that the conditions are different:

- **The goal is the artefact**, not your capability. Nobody is assessing whether
  you personally can write it.
- **You can still tell whether it works.** You may not be able to produce it, but
  you can specify it, test it, and recognise it failing. That is real control —
  though not complete control, and it's worth knowing where it runs out. It
  holds for code that fails *visibly*. It does not hold for race conditions,
  security properties, numerical stability, or anything that fails rarely,
  silently, or later. Code can pass every test you thought to write and still be
  wrong in the way that eventually bites.
- **You accept the debt knowingly.** If it breaks at 2am, you're the one who
  learns it then. Fine — as long as that was a decision rather than a surprise.

None of those hold for a problem set. The goal there *is* your capability, the
assessment *is* of you, and there is no artefact anyone wants — the linked list
has been written. So the same act that's ordinary professional judgement in a job
is, in a course, just skipping the thing you're paying to acquire.

Which is why the line is drawn where it is: **there's a time and a place for
handing over code you can't write, and it's almost never schoolwork.**

## Sturdier versus bigger

There's a second question underneath the first, and it's the one that comes up
in real projects: is it alright to let it take your design **further** than you'd
have taken it — more robust, more finished — rather than just writing code you
couldn't?

Those are two different requests with opposite risk, and they get said in one
breath.

**Making it sturdier is close to the best use there is.** Handling the
disconnect you didn't consider. Validating the input you assumed. Noticing the
state transition you left unhandled. You can almost always understand every one
of those the moment you see it — what you lacked wasn't ability, it was
**exposure to a standard**. Six weeks into a domain, nobody has a model of what
"done properly" looks like in it. An agent supplying that is doing what a good
senior engineer does in review, and nobody thinks being reviewed is cheating.
The additions are also small, local, and sit next to code you wrote, so each one
teaches a habit you keep.

**Making it bigger is the one to be suspicious of**, and not mainly for learning
reasons. Robustness deepens what already exists; features widen it. Every one you
didn't design yourself grows the share of the system you don't hold in your head
— and scope you didn't choose is how a project becomes unmaintainable by its own
author. In a design project that arrives at the demo, in a subsystem you have
never once debugged.

> **Let it make your thing sturdier. Be much more careful when it makes your
> thing bigger.**

## Design projects, which are both at once

The acquiring/applying split above is clean and real projects aren't. A capstone,
a competition robot, a group build: the artefact genuinely has to work, *and*
you're being assessed, *and* the learning is supposed to happen anyway. That's
most of what an engineering degree actually asks of you, and neither column of
the table describes it.

Two things worth holding onto there:

**Depth is the axis, not permission.** One step past your reach is where you
learn. Three steps past is where you end up maintaining a stranger's system with
your name on it — and the deadline arrives before you can read your way back in.
"How far past me is this?" is a better question than "am I allowed to use this?",
and you can ask it honestly about each piece.

**It's a team problem too, not just a personal one.** A subsystem one person
generated and nobody understands is the thing that cannot be fixed the week
before the deadline, because its author was never really its author. If you can't
walk a teammate through it, it isn't finished, whatever it does when you run it.

## The part that doesn't atrophy

Some things genuinely get worse with heavy agent use. Recall of exact syntax
goes first, and that one barely matters — you'll look it up, everyone always
did.

Debugging is the one to protect. It's the skill with the longest build time, the
one that transfers across every language you'll ever use, and the easiest to skip
by pasting an error and taking the answer. Guard it deliberately: give yourself a
fixed window — ten minutes, twenty — on your own before you hand over an error.

And note what *doesn't* erode, because it's the part you're actually in school
to acquire: deciding what to build, judging whether a design fits the problem,
knowing that a result is wrong before you know why. The agent is weakest exactly
there. It cannot do the judgement for you, so using it doesn't cost you the
practice.

## The academic-integrity question, briefly

Separate from learning, and not one this document can answer: **your institution
has a policy, it varies by course, and you are responsible for reading it.**
Some courses forbid AI use outright, some require disclosure, some encourage it.
"I didn't know" has never worked as a defence for anything.

Assume the rule is stricter than you'd like, ask the instructor if it's
ambiguous, and don't let a tool decide an integrity question for you. This kit
has no opinion on what your course allows. It has a strong opinion that you
should find out.

## The honest summary

Used carelessly — accepting what you don't understand because it runs — this
will hollow out your competence while making you feel productive, and you will
not notice for a year.

Used deliberately, it's closer to having a patient expert on call: one that
explains, reviews, argues, and lets you get further into interesting problems
than you could alone. Students who use it that way don't learn less. They spend
less time stuck on the boring kind of stuck.

The difference is entirely in what you ask for, and nobody supervises it but you.

And it's worth saying that this is a question with an expiry date on it. The
habits above are for the years when your capability is the product. Once it
isn't — once you're being paid for working software rather than assessed on
knowing how — the calculation genuinely changes, and most of the caution in this
section stops applying. Learn the discipline while it matters. Keep the reviewing
and drop the rest.

---

Next: **`03-WHY.md`** — the tools underneath all of this, and why the setup is
built the way it is.
