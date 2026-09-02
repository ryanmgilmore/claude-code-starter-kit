# Licensing

Two licences, because this directory holds two different kinds of thing.

| What | Licence | File |
|---|---|---|
| The documents — every `.md` file here | **CC BY-SA 4.0** | `LICENSE` |
| The scripts — everything in `templates/` | **MIT** | `LICENSE-CODE` |

## Why the split

Creative Commons licences are written for prose and are the right fit for the
documents. Creative Commons themselves recommend against using them for
software: they don't distinguish source from object code, carry no patent
grant, and lack the warranty and liability terms software licences are built
around.

ShareAlike would also work against the point of `templates/`. Those scripts
exist to be copied into your own workspace and changed — that is the entire
reason they ship. Under a ShareAlike licence, your modified copy would have to
carry the same licence, which collides with whatever your own project already
uses. MIT lets you take them, change them, and license the result however you
like. Keep the copyright notice and you're done.

## What ShareAlike does and doesn't require

The documents are BY-SA because if someone builds a course, a handbook or a
guide **out of** this material, that derived work should stay open the way this
one is. Concretely, ShareAlike applies when you produce **adapted material** —
the licence's term for the original "translated, altered, arranged, transformed,
or otherwise modified". Editing these documents, excerpting and reworking them,
translating them, or building new teaching material on top of them all qualify,
and the result must be BY-SA too.

It does **not** reach across a bundle. Handing these documents out unmodified
alongside your own course notes does not place your notes under BY-SA. Nothing
in a Creative Commons licence does that, and a licence that tried would not be
an open licence any more.

## Using it

Attribution is the only condition on the documents beyond ShareAlike: name the
source and link back. Nothing here is warranted for any purpose — read
`01-WORKING-WITH-AN-AGENT.md` and `06-DAILY-USE.md` before running scripts that
touch your files, and understand what they do first.
