# Correct-fix example; Python rules

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Covers Ruff codes (`F*`, `E*`/`W*`, `B*`, `UP*`, `SIM*`, `S*` 3-digit, `PL*`, `C901`, `N*`, `ARG*`, `PTH*`, `TID*`, `TC*`, `I*`, `RUF*`) and type-checker findings (pyright `reportXxx` names, mypy error codes like `[arg-type]`).

## Steps

### 1. Check the example library first

`@references/python/rules/<CODE>.md` is the library: one file per rule, already in the output format. When the file exists, serve it; adapt the wrong snippet to the user's real code when they gave a concrete file, otherwise return it as is. Steps 2–5 are for codes with no library file.

### 2. Establish the rule's intent

- Ruff bundles its rule docs offline: `ruff rule <CODE>` prints the full description with noncompliant/compliant examples (install first if missing: `pip install ruff`). The output names the rule; the web doc lives at `https://docs.astral.sh/ruff/rules/<kebab-case-rule-name>/`; the URL keys on the **name**, not the code.
- pyright findings (`reportOptionalMemberAccess`, ...): the configuration table at https://microsoft.github.io/pyright/#/configuration. mypy codes (`[arg-type]`, ...): https://mypy.readthedocs.io/en/stable/error_code_list.html.
- A fix based on a misremembered intent is worse than none.

### 3. Establish the context

The source of truth is the **target repo's** Ruff config (`ruff.toml` or `[tool.ruff]`); when the repo has none, fall back to the **Kit config** line each `@references/python/rules/` file carries. The main context splits:

- tests: `S101` (assert) and `PLR2004` (magic values) are legitimately off in `tests/**`; an assert finding from a test file usually means the per-file-ignores don't cover that path, not that the assert is wrong
- complexity limits (`C901`, `PLR0913`, `PLR0912`): the fix is splitting, and where the split lands differs; domain code splits by concept, adapters may legitimately sit at the limit
- domain code: time, randomness, and I/O arrive as parameters; a `DTZ`/`S311` style finding in the domain is an injection problem, not a call-site problem

If the warning comes from a concrete file, build the wrong snippet from the real code, minimized. Without one, write the canonical example.

### 4. Write the fix in modern Python (3.12+) idioms

- type hints with builtin generics (`list[str]`, `X | None`), no `typing.List`
- `pathlib.Path` over `os.path`; f-strings; `match` where it beats if-chains
- dataclasses (`slots=True`) or Pydantic for data shapes; `enum.StrEnum` for closed sets
- time and identity injected: `datetime.now(tz=UTC)` never naive, and in domain code the timestamp/id arrives as a parameter
- exceptions: `raise ... from err` (B904), no bare `except:` (E722), no silent `pass` swallow
- phrase the principle sentence concretely: "6 parameters → group the ones that travel together into a dataclass", not "violates SRP"

### 5. Verify proportionally

Write the wrong snippet to the scratchpad and check it fires, then that the right one is silent:

```bash
ruff check --isolated --select <CODE> snippet.py
```

(`--isolated` ignores any config on disk, so the test is exactly the one rule.) Type-checker snippets: `pyright snippet.py`. A single-token change may skip verification.

### 6. Grow the library

Save the newly written example as `@references/python/rules/<CODE>.md` in the format the existing library files use (open any one as the template), so the next request for this code is a lookup, not a rebuild.

## Language-specific Done-when additions

When the finding is legacy debt rather than new code, the freezing techniques to offer are: `ruff check --select <CODE> --add-noqa .` for the rule, a `per-file-ignores` entry for the legacy directory, or (type findings) removing the directory from pyright's top-level `strict` array / overriding the tripped `report*` rules for it in an `executionEnvironments` entry.
