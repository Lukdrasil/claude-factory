# factory curate

Walks the proposal queues (repo, global and agent memory, ADR, architecture) one proposal at a time, through
`<plugin-root>/bin/curate-apply.sh`. Every decision is one commit in `<root>/state`.

## Automatic vs manual

`curation: auto|manual` in `<root>/state/factory.yml`, absent means `auto`. Under `auto` a session ends by
spawning `memory-curator` over its own proposals, applied with `curate-apply.sh ... --reason "<text>"`, the
agent held gate standalone (ADR-0052); this skill skips those. Under `manual` every proposal stays human.

## When

- `curation: manual`, after a session left proposals behind;
- on request, whatever `curation:` says.

## Steps

- **List.** `<plugin-root>/bin/curate-apply.sh list --state <root>/state`, `<root>` being `WORK_DIR`.
  Completion: the paths are in front of you, in that order; an empty list is the whole report.
- **Show.** Print the next proposal in full. Completion: the human has read the text, not a summary.
- **Ask.** One ask (`_shared/ask.md`) per proposal, three options: approve, naming the default target, the
  path without `proposals/` (an ADR proposal is numbered on approval, `ADR-NNNN-<slug>.md`), or the target the
  human names instead when it lies under one of the five roots; reject; edit, then ask for the new text.
  Completion: one answer recorded.
- **Apply.** `curate-apply.sh approve <path> [<target>] --state <root>/state`, `... reject <path> ...`, or
  the new text into a file and `... edit <path> --body <file> ...`. Exit 1 prints the reason, a taken target
  or a wrong shape: show it and ask again. Completion: exit 0 and one new commit; an edited proposal stays
  in the queue with its new text.
- **Next.** On to the next path until the list is done. "Approve them all" is answered the same way, one
  proposal shown and asked at a time. Completion: every listed path has a decision.
- **Report.** The counts per decision and the target of each approved proposal.
