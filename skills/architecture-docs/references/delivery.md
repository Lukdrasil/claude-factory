# Delivery

Read alongside step 9 of `<plugin-root>/skills/architecture-docs/SKILL.md`. One branch, one MR, in the
product repo. The branch is `docs/architecture-<bootstrap|audit>-<YYYY-MM-DD>`, and the commit contains
`docs/**`, `CONTEXT.md` and `README.md` and nothing else.

- **Task mode**: the forge flow in `## Output` of `<plugin-root>/skills/_shared/session-contract.md`. Rebase
  on the base branch, `git push --force-with-lease origin <branch>`, create the MR through `gh` or `glab` only when there is not one
  already, write the web URL into `mr_url`.
- **Local session**: push the branch, then create the MR with `gh` or `glab` when
  `sh <plugin-root>/bin/forge.sh hosts` shows you signed in to the host of `git remote get-url origin`.
- **Fallbacks**, in order: not signed in to that host, push the branch and tell the human the MR is theirs to
  open; no push access, leave the commit on a local branch and say so. A fallback is reported, never silent.

## The description

It carries the mode, the documents written, every `TODO(question)` still open, and the options and
recommendations the human has not answered. **Under 300 words**: mode and document count in the first line,
then one line per open question, being the question, its options and your recommendation. The documents
carry the content, so the description neither restates them nor recounts the exploration.

It ends with the receipt, after the open questions:

```
claims: N confirmed / N diverged / N ungrounded
doc-facts: N mismatch
doc-cites: N dead
arch-build: passed | skipped
arch-delta: N changes | skipped
mermaid: N/N rendered | skipped (no renderer)
evidence_rounds: 0 | 1 | 2
```

Every line is an independent claim about what actually ran, written from that run alone. A check that did not
run reads `skipped`, and `skipped` is never rewritten as `passed` because the rest of the audit went well.
The block does not count towards the 300 words.
