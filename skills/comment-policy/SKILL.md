---
name: comment-policy
description: The test every comment line in code has to pass before it is written, and the four allowed classes with their prefixes. Use at the moment you are about to write a comment, when the comment gate denies an edit, and when a review asks whether a comment earns its line.
---

# Comment policy

The target is zero comment lines: a comment is a claim the compiler never checks and the next edit silently
breaks. `${CLAUDE_PLUGIN_ROOT}/bin/comment-gate.sh` enforces the classes below on every edit in a task
worktree.

## The three questions

Ask them in order, before the comment exists.

1. **Derivable?** Could a reader get it from the code, a name, a signature, a test or a doc in the repo?
   Then rename, extract a method, or add a test.
2. **Checkable?** Could it be a type, a guard clause, an assertion, a test, a benchmark or a linked ticket?
   Then write that instead.
3. **Anchored?** What is left carries a class prefix and the anchor its class asks for, or it is not written.

## The four classes

| prefix | carries | the anchor |
|---|---|---|
| `why:` | the non-obvious reason for a choice, a workaround, a measured performance shape | the reason; a link for a workaround, the numbers for a measurement |
| `invariant:` | what must hold that the type system cannot say | the relying code, named |
| `warn:` | the non-obvious consequence of changing this line | the thing that breaks, named |
| `see:` | a spec, RFC, ADR, issue or design doc that settles the shape | the link or id, plus what it settles |

The prefix follows the file's comment marker. A doc comment on a public API, a shebang, a license header
and a justified tool directive pass as they are.

## Forbidden, with the replacement

- **Restated code**, prefixed or not: a better name says it.
- **Section headers**: the member is too long to show its own shape; extract.
- **Commented-out code**: delete, git history has it.
- **A note left for later** without a ticket: fix it now, or `see:` the ticket.
- **Author, date, history, intent of the change**: the commit message and the progress file.
- **Tool stubs** left unedited: delete or fill.

## Steps

1. **Before writing a comment**, run the three questions. Done when the line is deleted, replaced by code,
   or written with its prefix and anchor.
2. **When the gate denies an edit**, take every line it names through the questions and rewrite the edit,
   never the policy. Done when the retry passes.
3. **When reviewing**, walk every comment line the diff adds: unprefixed, failing question 1, or missing its
   anchor is a finding naming the replacement. Done when every added comment line has a verdict.

## References

- `${CLAUDE_SKILL_DIR}/references/classes.md`: every class, its verdict, its authority, its replacement.
- `${CLAUDE_SKILL_DIR}/references/research.md`: the sourced research behind the classes.
