# Installing agent guardrails; Python

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Stack: **Ruff** (linter + formatter, replaces flake8/isort/pyupgrade/black), **pyright** (type check; mypy stays if the repo already uses it), **import-linter** (architecture boundaries, optional). Sources are the files in `@references/python/`; installed files land in the **target repo root**.

**Invariant: every step ends green**; `ruff check` exit 0 and the type checker exit 0. Existing debt gets frozen with @references/python/BASELINE.md, never mass-fixed during install.

## Steps

### 1. Preflight

- Verify the current state runs (tests pass or at least the package imports) before touching anything.
- Inventory existing lint tooling: `.flake8`, `[tool.flake8]`/`[tool.isort]`/`[tool.black]`/`[tool.pylint]` sections, `.pylintrc`, `setup.cfg` lint sections, an existing `[tool.ruff]` in `pyproject.toml`. Ruff replaces flake8+isort+pyupgrade+black; list what would be retired and get the user's OK before removing configs.
- Config placement: default is the standalone `@references/python/ruff.toml` → repo-root `ruff.toml` (it can then be protected by permission deny). If the repo already configures Ruff in `pyproject.toml`, **merge there instead**; two config files would shadow each other (`ruff.toml` wins silently).
- Type checker choice: repo already runs mypy (config or CI job exists) → keep mypy and use `mypy-baseline` for freezing (@references/python/BASELINE.md, technique C). Otherwise install pyright.
- A src-layout repo without a `[build-system]`/editable install is not importable as-is: tests need `PYTHONPATH=src` and pyright needs `extraPaths` (step 4). Record it; fixing packaging is out of scope for the install.

### 2. Measure and pick the starting strictness

Run the kit config against the code before installing it:

```bash
pip install ruff==0.16.3
ruff check --config <path-to-@references/python/ruff.toml> --statistics .
```

(`--statistics` prints count per rule code.) **Decision rule**: rules with up to ~20 findings → keep enabled, fix or freeze per line (technique A); rules with hundreds of findings → freeze per directory (technique B) or drop the whole group from `extend-select` and record it as debt with a re-enable plan. The curated `extend-select` list in `@references/python/ruff.toml` is the goal state; what gets trimmed now goes into the report as debt.

### 3. Install the linter + formatter

- Copy `@references/python/ruff.toml` to the repo root (or merge into existing `[tool.ruff]`), adapting: `target-version` from `requires-python`, `src`/per-file-ignores paths to the real layout, and the trims decided in step 2.
- Pin the tool: add `ruff==0.16.3` to the dev dependencies (a new minor version changes the default rule set; an unpinned ruff red-builds by itself).
- Freeze remaining findings per @references/python/BASELINE.md until `ruff check .` is green.
- Formatter: `ruff format .` on a legacy repo is one big atomic commit; offer it to the user. If declined, leave the `ruff-format` job out of CI and note it in the report.

### 4. Type checker

Copy `@references/python/pyrightconfig.json` to the repo root (pyright rejects unknown keys, so keep it comment-free) and adapt to the real layout: `include`/`extraPaths`, and the top-level `strict` array, the escalation mechanism, listing directories checked in strict mode (domain/core packages; the rest run at the global `standard`). A src-layout repo without an editable install needs `extraPaths: ["src"]`, otherwise every internal import reports as missing. Install and run: `pip install pyright` then `python -m pyright` (the pip Scripts dir is often off PATH, notably with Windows Store Python, `python -m` always works). Red → shrink the `strict` list or freeze per technique C, never lower the global mode. Green before moving on. (Mypy path: keep the existing config, add `mypy-baseline` so CI fails only on new errors.)

### 5. AGENTS.md; the rules for agents

From `@references/python/agents/AGENTS.md.template`, copy only the fenced markdown block into `AGENTS.md` at the repo root. Rewrite the Architecture section to the repo's actual layers; keep the FORBIDDEN CHANGES section's wording and prohibitions intact, fixing only the file paths. If the team uses Copilot, duplicate into `.github/copilot-instructions.md`.

### 6. Permission deny

Merge `@references/python/agents/claude-settings.json` into the target repo's `.claude/settings.json` (keep existing permissions, drop `_comment`). Adjust paths to where the files actually landed. Note the residual gap: inline `# noqa` / `# type: ignore` cannot be denied by permission; the AGENTS.md prohibition covers it.

### 7. Pre-commit (optional)

Offer `@references/python/pre-commit-config.yaml` → `.pre-commit-config.yaml` (`pip install pre-commit && pre-commit install`). Local loop auto-fixes; the hard gate stays in CI.

### 8. CI gate

Merge `@references/python/gitlab-ci.yml` into the repo's CI (or its equivalent for another CI system). The `ruff check` job uses `--output-format=gitlab` for MR annotations. If the user declines CI, record that enforcement stays advisory.

### 9. Optional: architecture boundaries

When the repo has (or adopts) a layered package structure, copy `@references/python/importlinter` to the repo root as `.importlinter`, replace `__PACKAGE__` and the layer list with the real packages, add `import-linter` to dev dependencies, and get `lint-imports` green (freeze exceptions via the contract's `ignore_imports` if needed). This is the Python equivalent of the .NET branch's architecture tests.

## Done when

`ruff check .` and the type checker are green, the files from steps 3–8 are in place, `AGENTS.md` describes the repo's real structure, and the report to the user contains: per-rule counts from step 2, what was trimmed or frozen (= debt with re-enable plan), formatter adoption status, and CI enforcement status.
