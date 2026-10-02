# UI round

Held once per grill, as soon as a `research` row settles that the change touches a surface a person sees:
a web page or component, a form, a dialog, an email, a CLI or TUI output, a report layout. A change with no
such surface skips this file. Held in `--auto` too: it is the fifth case of `_shared/auto-decision.md`, and
the recommendation is never taken for the human here.

## Skipped when the task settles it

Read the task before you ask: `## Context`, the human's words under `## Internal` and `## Solution`, and the
spec as given. The round is not held, and the row closes with the answer the task gave, when either holds:

- the task names what the result looks like: a design or mockup link, a screenshot or attachment, a page or
  component to copy, a sentence that describes the layout. That is the variant; the design round sketches it
  and the proposals that build it name it under `context:`.
- the task leaves the look to the agent: `no mockup`, `look as you see fit`, `follow the existing UI`, or
  words to that effect. The row closes with `agent decides`.

Say in one line which of the two the task settled and where it says so. Ask when the task says neither, or
says both.

## The question

One round, in the interview format, before the design round:

```
❓ **Q<n>** - **The look of the change** (after Q<the row that found the surface>): the change reaches
<the surface, named>. Two ways to settle how it looks.
  **A** a mockup: I write one HTML page with two to four variants of the result, you pick one, and the pick
        becomes a decision the design and the blocks build against
  **B** the agent decides: the look follows the existing surface and its conventions, and the review of the
        task MR is where you see it

➡️ **<A|B>**: <one paragraph: A when the surface is new or the variants differ in what the user does, B when
the change fits an existing pattern and a mockup would only redraw it>
```

A `B` closes the row with `agent decides` and the grill goes on. The row is `decision`, `deps` the row that
found the surface.

## The mockup

On `A`, write `<state>/repos/<repo-key>/research/<id>-ui-mockup.html`: one self-contained page, no external
script or stylesheet, with every variant as its own section, labelled `Variant A`, `Variant B`, ..., at most
four. Each variant shows the result after the change, in the repository's own terms and with its real
vocabulary (`## Terms`), with one line under it on what differs from the others: what the user does, what
they see first, what it costs in code. Where the repository has a design system, a component library or a
stylesheet, read it first and draw with its names and look; a mockup in a foreign style decides nothing.
Static markup is enough: no interaction has to work. Commit it in the state clone
(`state-commit.sh -m "research: <id> ui mockup" --state <state> -- repos/<repo-key>/research/<id>-ui-mockup.html`).

When the session has the Artifact tool, publish the same file through it and give the link; otherwise give
the path and say to open it in a browser. Then one more round:

```
❓ **Q<n+1>** - **The variant** (after Q<n>): <the link or path>
  **A** Variant A: <its one line>
  **B** Variant B: <its one line>

➡️ **<letter>**: <why>
```

`explore` and `more` work as in the interview loop; a change the human asks for on a variant is a redraw of
that variant and the question again. The pick closes as a `[locked]` decision when it passes the three gates,
and the design round sketches that variant and no other; the proposals that build it name the mockup file
under `context:`, so an implement session sees the target.
