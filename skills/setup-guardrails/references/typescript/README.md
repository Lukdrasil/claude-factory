# Installing agent guardrails; TypeScript / JavaScript

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Stack: **ESLint 10** (flat config only) + **typescript-eslint 8** with type-checked rules, **tsc** strict flags, **bulk suppressions** for debt freezing. Verified versions: `eslint@10.8.1`, `typescript-eslint@8.67.0`, `@eslint/js@10.0.1`; the repo's existing `typescript` (5.x+) stays. Sources are the files in `@references/typescript/`; installed files land in the **target repo root** (monorepo: the workspace root, with `files` globs per package).

**Invariant: every step ends green**; `npx eslint .` exit 0 and `npx tsc --noEmit` exit 0. Existing debt gets frozen with @references/typescript/BASELINE.md, never mass-fixed during install.

Biome note: a greenfield repo that wants one fast tool and no ESLint-only plugins may prefer Biome 2.x (lint+format in one). This guide installs the ESLint path; it is the one with type-aware fidelity and the plugin ecosystem; mention the Biome option to the user only when the repo has no ESLint history at all.

## Steps

### 1. Preflight

- Verify green before touching anything: `npm ci` works, existing `tsc`/lint scripts pass.
- Inventory existing tooling: `.eslintrc*` (legacy format, ESLint 10 ignores it, must be migrated to flat config), existing `eslint.config.*`, Prettier config, Biome config. Rule: **merge, not overwrite**, an existing flat config gets the kit's blocks added; a legacy `.eslintrc` gets migrated (list every rule whose severity changes).
- Formatter: keep the repo's existing Prettier if present (add `eslint-config-prettier` last in the extends chain to kill conflicting stylistic rules). No formatter → offer Prettier or Biome format; record the choice.

### 2. Measure and pick the starting strictness

Install dev deps and copy `@references/typescript/eslint.config.js` into the repo root (step 3 merges into it afterwards); the config's own `import`s resolve from the config file's location, so `--config` pointed into the skill folder fails with `ERR_MODULE_NOT_FOUND`:

```bash
npm i -D eslint typescript-eslint @eslint/js
npx eslint . 2>&1 | tail -5
```

The summary line gives error/warning counts. **Decision rule**: under ~200 findings → keep `recommendedTypeChecked` + `stylisticTypeChecked` and freeze the rest; over ~1000 → start from `recommended` (non-type-checked) and record the type-checked configs as the escalation goal; `strictTypeChecked` is always an escalation step, never the start (typescript-eslint's own guidance: only for teams highly proficient in TS).

### 3. Install the linter

Merge `@references/typescript/eslint.config.js` at the repo root (already copied in step 2), adapting `files` globs and the test-override paths to the real layout. When `package.json` lacks `"type": "module"`, name the file `eslint.config.mjs`; same content, without Node's per-run `MODULE_TYPELESS_PACKAGE_JSON` warning. Plain-`.js` sources outside the tsconfig need `parserOptions.projectService.allowDefaultProject`. Freeze existing findings: `npx eslint . --fix --suppress-all` → commit `eslint-suppressions.json` (@references/typescript/BASELINE.md, technique A). Verify `npx eslint .` is green.

### 4. Compiler strictness

Merge `@references/typescript/tsconfig.strict.json` flags into the repo's `tsconfig.json` `compilerOptions`. Count errors after each flag (`npx tsc --noEmit | wc -l`): singles-to-tens → fix now; hundreds → back the flag out and record it as debt (technique B; tsc has no baseline mechanism). A flag whose errors are about the repo's **configuration** rather than its types (`verbatimModuleSyntax` under `module: "commonjs"` → TS1287/TS1295) also gets backed out as debt; reworking the module system is an architectural decision, not a guardrails install. `strict: true` itself must survive; a repo that cannot hold it gets `strict` per sub-project via project references, noted in the report. Verify `npx tsc --noEmit` green.

### 5. AGENTS.md; the rules for agents

From `@references/typescript/agents/AGENTS.md.template`, copy only the fenced markdown block into `AGENTS.md` at the repo root. Rewrite the Architecture section to the repo's actual layers; keep the FORBIDDEN CHANGES section's wording and prohibitions intact, fixing only the file paths. If the team uses Copilot, duplicate into `.github/copilot-instructions.md`.

### 6. Permission deny

Merge `@references/typescript/agents/claude-settings.json` into the target repo's `.claude/settings.json` (keep existing permissions, drop `_comment`). Adjust paths (monorepo: per-package tsconfig paths). Residual gap: inline `// eslint-disable` / `@ts-expect-error` cannot be denied by permission; the AGENTS.md prohibition covers it; `eslint-suppressions.json` **is** denied, so the agent cannot silently grow the frozen debt.

### 7. CI gate

Merge `@references/typescript/gitlab-ci.yml` into the repo's CI (or its equivalent). `--max-warnings 0` makes warnings block in CI while staying advisory locally; `--pass-on-unpruned-suppressions` keeps fixed-debt entries from failing the build (prune them in cleanup sessions instead). If the user declines CI, record that enforcement stays advisory.

### 8. Optional escalations

On request, per repo shape: `eslint-plugin-boundaries` (layer boundaries as lint feedback) or `dependency-cruiser` in CI (cycles, orphans); the TS equivalent of the .NET branch's architecture tests; `eslint-plugin-unicorn`, `eslint-plugin-import-x`, `eslint-plugin-sonarjs` for wider rule coverage; `knip` for dead code (start `--no-exit-code`, technique C). Each addition follows the same loop: measure → freeze → green.

## Done when

`npx eslint .` and `npx tsc --noEmit` are green, the files from steps 3–7 are in place, `eslint-suppressions.json` is committed and counted, `AGENTS.md` describes the repo's real structure, and the report to the user contains: measured counts, the chosen config tier and escalation goal (`strictTypeChecked`, remaining tsc flags), suppression count (= debt), formatter decision, and CI enforcement status.
