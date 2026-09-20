# Debt freezing; Python

Goal: full rules for **new** code without the existing code turning the build red. Every technique below is debt to pay down, not a hiding place.

## Technique A; `--add-noqa` (per rule, per line)

Ruff's official way to enable a rule on a legacy codebase:

```bash
ruff check --select PLR0913 --add-noqa .
```

Inserts `# noqa: PLR0913` at every existing occurrence; from then on the rule applies only to new code. Use for rules with tens of findings.
Debt metric: `grep -rc "# noqa" src/ | awk -F: '{s+=$2} END {print s}'`.

## Technique B; `per-file-ignores` (per directory)

For directories in end-of-life mode; coarser, but without thousands of comments in the code:

```toml
[lint.per-file-ignores]
"src/app/legacy/**/*.py" = ["PL", "C90", "S"]
```

## Technique C; type-checking debt

- **pyright**: keep the global `typeCheckingMode`, escalation = adding directories to the top-level `strict` array; a directory that cannot hold `standard` yet gets an `executionEnvironments` entry overriding the individual `report*` rules it trips (entries accept `root`, `extraPaths`, `pythonVersion` and per-rule severities, `typeCheckingMode` is **not** a valid per-environment setting; pyright rejects it).
- **mypy** (when the repo already uses it): the `mypy-baseline` package (orsinium-labs/mypy-baseline); the first run records existing errors into a baseline file; CI then fails only on new errors.

## Paydown rule

Every freeze gets an issue with a deadline. A baseline without a plan is just a slower way to disable the rule. Track the trend with the technique-A number in the CI report.
