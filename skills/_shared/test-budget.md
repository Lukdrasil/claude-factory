# Test budget

Every test or build command runs under a wall-clock cap: `timeout 15m <command>`. The policy guard denies a
bare `dotnet test` (T-036: a hung test host kept a session waiting for 20 minutes of dead time, with no trace
of which test hung).

When the cap fires (exit 124):

1. Write what the run did print into the progress file, partial output is the diagnostic, not noise.
2. Retry **once** with hang diagnostics so the hanging test gets a name: on VSTest
   `timeout 15m dotnet test --blame-hang-timeout 10m --blame-hang-dump-type none`; on MTP add
   `--hang-dump --hang-dump-timeout 10m` if the repo carries the HangDump extension, otherwise skip the retry.
3. Still hanging → self-report per your skill's contract (`failed`, with the budget overrun and the suspected
   test in the reason). Never wait it out: a session waiting past its budget burns the time and throws away
   the diagnosis you already have.

Polling a run in the background follows the same rule: the **total** wait is bounded by the same budget, never
an open-ended sleep loop.
