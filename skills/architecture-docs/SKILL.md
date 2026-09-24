---
name: architecture-docs
description: Writes and maintains a product repo's architecture and product documentation, docs/architecture/, docs/product/ and CONTEXT.md, in the modes bootstrap and audit. You analyse and write, the human decides. Use for "document the architecture", "bootstrap the docs", "the architecture docs are out of date".
---

# architecture-docs

Plugin root: `${CLAUDE_PLUGIN_ROOT}`. You author `docs/product/`, `docs/architecture/` and `CONTEXT.md` of
the **product repo**. You assist, you never decide: every architectural question reaches the human as
options, their consequences and your recommendation, confirmed before it is written. Anything left open is
a one-line `TODO(question)`, never a guess.

## Preconditions

- Mode is `bootstrap` without `docs/architecture/`, `audit` with it; an explicit argument wins, a
  contradiction flagged first.
- The entry point, its human and its write scope: `${CLAUDE_SKILL_DIR}/references/invocation.md`.
- You write only under `docs/`, `CONTEXT.md` and `README.md`; in task mode the policy-guard enforces it.

## Steps

1. **Read the references.** `references/templates.md` for the file set, the skeletons and the
   `template_version`, then `references/approaches.md` for the options; a domain rubric from
   `references/README.md` loads when its subject enters scope and outranks this file. Done when you can
   name the version and your documents.
2. **Fix mode, scope and sources.** `bootstrap` takes the whole file set, `audit` the whole solution unless
   narrowed, a narrowing recording what it leaves unchecked; `docs/adr/` is input. Done when all three are
   agreed with any human present.
3. **Explore the code** per `${CLAUDE_SKILL_DIR}/references/exploring.md`. Done when every deployable unit,
   datastore and external system carries a `path/file.ext`, every in-scope claim reads confirmed, diverged
   or ungrounded, and `sh ${CLAUDE_PLUGIN_ROOT}/bin/doc-cites.sh <product-repo>` reports no MISMATCH off
   that list.
4. **Consult the panel** per `exploring.md`: one `domain-architect` per domain whose `Load when` row
   hits, in parallel, each given the domain and the absolute paths of the repo,
   `architect-review/references/checks.md` and `references/README.md`. Done when every in-scope domain has a
   report and every finding is drafted, a divergence, or dropped with a reason.
5. **Draft.** `architecture/` from step 3, `product/` from the interview alone: business intent is not in code.
   Every choice enters as two or more options from `approaches.md`, each with its consequence for the
   quality scenarios and constraints **by id** and its reversal cost. Done when nothing
   is proposed alone.
6. **Interview, document by document**, in file-set order: draft or questions, options with consequences,
   your recommendation and its driver, the choice read back before writing. Done when every section is
   confirmed or carries a TODO question.
7. **Write** per `templates.md`, stamped with the current `template_version`; in `audit` compare the stamp
   first and offer the re-shape before judging drift, a removal being a proposal. Done when every document
   meets its "Done when", `grep -rn 'TODO(question)' docs/ CONTEXT.md` returns only open
   points, and every mermaid fence was rendered or the receipt says so.
8. **Record each accepted choice** as an ADR under `docs/adr/` with the rejected options and why. Done when
   `03-containers.md` points at an ADR id per choice.
9. **Deliver** per `${CLAUDE_SKILL_DIR}/references/delivery.md`. Done when you report the MR web URL, the
   pushed branch, or the local branch and why.

