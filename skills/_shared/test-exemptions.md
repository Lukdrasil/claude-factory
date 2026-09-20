# Test exemptions

Code whose only job is **development orchestration** carries no unit tests. That is the Aspire AppHost and
nothing else around it: `*.AppHost/**`, `AppHost.cs`, `apphost.cs`, `apphost.mts`, plus the compose and
dev-run wiring that starts the same solution locally.

Why it is an exemption and not a gap: the file is declarative wiring. A unit test over it asserts the wiring
back to itself, passes by construction, and goes red on every resource rename. What proves it is the
orchestrator starting and the resources coming up, which is a run, not a test.

The exemption covers the wiring only. Anything the orchestration calls into, a helper, a parser, a health
check with a branch of its own, is ordinary product code and is tested like any other.

Consequences, so no session re-litigates it:

- **block-tests:** no characterization and no red tests for exempt files. List them under `Notes` in
  `## Handoff` with the word `exempt`, so the implement phase does not go looking for a contract.
- **`## Quality`:** exempt methods stay out of the CRAP table. When the diff is exempt files only, the
  section is one line: `dev orchestration only, test-exempt`.
- **review:** a missing test over an exempt file is not a finding. A test-free file that is not on the list
  above still is, and so is product logic moved into an AppHost file to ride the exemption.
