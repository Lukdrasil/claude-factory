---
name: comment-policy
description: The test every comment line in code has to pass before it is written, and the one class that passes. Use at the moment you are about to write a comment, when the comment gate denies an edit, and when a review asks whether a comment earns its line.
---

# Comment policy

This harness writes no comments in code. A comment is a claim the compiler never checks and the next edit
silently breaks. `${CLAUDE_PLUGIN_ROOT}/bin/comment-gate.sh` enforces the one exception below on every edit in
a task worktree.

## The two questions

Ask them in order, before the comment exists.

1. **Derivable?** Could a reader get it from the code, a name, a signature, a test or a doc in the repo?
   Then rename, extract a method, or add a test.
2. **Belongs elsewhere?** Is it the history, the intent of the change, a todo or a section header? Then it
   belongs in the commit message, the progress file or a task.

Nothing survives both questions as a comment. Write the code instead.

## The one exception

A documentation comment on a **public** class, interface or method: `///` in C# and F#, `/** */` in Java,
TypeScript and their family. It is written **only where the contract is not obvious from the signature**, and
it stays short: one summary sentence, plus the parameters, the return or the exceptions a caller cannot infer.
A doc comment that restates the member name is the restated-code case wearing a doc marker.

Nothing internal, private or local carries one.

A shebang, a license header and a directive a tool reads (`# shellcheck`, `# pragma:`, a suppression with its
justification) pass as they are. They are not comments for this policy.

## Forbidden, with the replacement

- **Any comment inside a member body**: a better name, an extracted method, a guard clause or a test says it.
- **A prefixed note** (`why:`, `invariant:`, `warn:`, `see:`): write the assertion, the test or the linked
  ticket the note points at.
- **Restated code**: a better name says it.
- **Section headers**: the member is too long to show its own shape; extract.
- **Commented-out code**: delete, git history has it.
- **A note left for later**: fix it now, or open a ticket.
- **Author, date, history, intent of the change**: the commit message and the progress file.
- **Tool stubs** left unedited: delete or fill.

## Steps

1. **Before writing a comment**, run the two questions. Done when the line is deleted or replaced by code.
2. **When the gate denies an edit**, take every line it names through the questions and rewrite the edit,
   never the policy. Done when the retry passes.
3. **When reviewing**, walk every comment line the diff adds: anything that is not a short doc comment on a
   public member is a finding naming the replacement. Done when every added comment line has a verdict.

## References

- `${CLAUDE_SKILL_DIR}/references/classes.md`: every class, its verdict, its replacement.
- `${CLAUDE_SKILL_DIR}/references/research.md`: the sourced research behind the policy.
