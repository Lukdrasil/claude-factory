# Comment classes, verdicts and replacements

Cut from `research.md`, where every authority below is sourced. A doc comment on a public type or member is
the only class the gate recognises; the research's `why:`, `workaround:`, `perf:`, `invariant:`, `warn:` and
`see:` classes are replaced by code, a test or a ticket.

| class | verdict | why | replacement |
|---|---|---|---|
| Restating the code ("increment i") | forbidden | Ousterhout 13.2: it could be written without seeing the code | a better name, or delete |
| Section header (`// ==== Setup ====`) | forbidden | the member is too long to show its structure | extract, or split the file |
| Commented-out code | forbidden | dead code posing as documentation; Sonar S125 | delete, git history has it |
| `TODO` / `FIXME` / `HACK` free text | forbidden | untracked notes rot; Sonar S1135, S1134 | fix now, or a ticket |
| Author, date, change history | forbidden | `git blame` answers it more reliably | the commit message |
| Intent of the change | forbidden | it belongs to the change, not the code | the commit message, the progress file |
| Tool-generated stub left unedited | forbidden | empty boilerplate is worse than none; Sonar S4663 | delete, or fill it |
| The non-obvious reason for a choice | forbidden | an unchecked claim the next edit breaks | a named constant, a named method, or a test that pins the choice |
| Workaround for an external defect | forbidden | it rots once the defect is fixed upstream | a named wrapper plus a test that fails when the upstream fix lands |
| Performance measurement behind an odd shape | forbidden | prose numbers go stale | a benchmark |
| Invariant the types cannot say | forbidden | Ousterhout 13.5 wants it enforced, not claimed | a guard clause, an assertion, a type, or a test |
| Warning of a non-obvious consequence | forbidden | a comment does not fail a build | a test that breaks when the consequence lands |
| Reference to a spec, RFC, ADR, ticket | forbidden in code | the commit message and the task carry the trail | the commit message, the MR description, the task |
| Regex or magic number explanation | forbidden | a naming failure | a named constant or a named method |
| Doc comment on a public API | allowed, only where needed | a compiler-checked contract (CS1591), read by tooling | one short summary plus the parameters a caller cannot infer |
| Suppression justification | not a comment, mandatory | an unexplained suppression is an unreviewed risk | the justification in the directive |
| License header, shebang, tool directive | not a comment here | legal or tooling convention | as it is |

A doc comment restating the member name is the first row wearing a doc marker, and the review's craft axis
reads it so.
