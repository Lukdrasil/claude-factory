# Comment classes, verdicts and replacements

Cut from `research.md`, where every authority below is sourced. The four prefixes are the whole vocabulary
the gate recognises: the research's `workaround:` and `perf:` fold into `why:` with a link or numbers as
the anchor.

| class | verdict | why | replacement or anchor |
|---|---|---|---|
| Restating the code ("increment i") | forbidden | Ousterhout 13.2: it could be written without seeing the code | a better name, or delete |
| Section header (`// ==== Setup ====`) | forbidden | the member is too long to show its structure | extract, or split the file |
| Commented-out code | forbidden | dead code posing as documentation; Sonar S125 | delete, git history has it |
| `TODO` / `FIXME` / `HACK` free text | forbidden | untracked notes rot; Sonar S1135, S1134 | fix now, or `see: <ticket> <what it settles>` |
| Author, date, change history | forbidden | `git blame` answers it more reliably | the commit message |
| Intent of the change | forbidden | it belongs to the change, not the code | the commit message, the progress file |
| Tool-generated stub left unedited | forbidden | empty boilerplate is worse than none; Sonar S4663 | delete, or fill it |
| The non-obvious reason for a choice | allowed | the class every authority carves out | `why: <reason>` |
| Workaround for an external defect | allowed, link required | unknowable from the code, removable once fixed upstream | `why: <link> <what it works around>` |
| Performance measurement behind an odd shape | allowed, numbers required | without it the shape reads as a bug | `why: <numbers or link>`; better, a benchmark |
| Invariant the types cannot say | allowed | "sorted", "caller holds the lock" have no signature; Ousterhout 13.5 | `invariant: <what holds> <who relies>`; better, a guard or assertion |
| Warning of a non-obvious consequence | allowed | it prevents a regression invisible locally | `warn: <what breaks>`; better, a test |
| Reference to a spec, RFC, ADR, ticket | allowed | it points at a checkable source | `see: <link or id> <what it settles>` |
| Regex or magic number explanation | allowed only when unnameable | usually a naming failure | a named constant, else `why:` |
| Doc comment on a public API | not a comment here | a compiler-checked contract (CS1591), read by tooling | as it is, on the public surface only |
| Suppression justification | not a comment, mandatory | an unexplained suppression is an unreviewed risk | the justification in the directive |
| License header, shebang, tool directive | not a comment here | legal or tooling convention | as it is |

The prefix is necessary, never sufficient: a `why:` restating the member's name is the first row wearing a
prefix, and the review's craft axis reads it so.
