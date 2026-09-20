# Correct-fix example; TypeScript / JavaScript rules

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Covers ESLint rules (core names like `eqeqeq`, plugin-scoped like `@typescript-eslint/no-floating-promises`, `unicorn/*`, `sonarjs/*`), tsc errors (`TS2345`), and Biome rules (`lint/...`; map to the closest ESLint rule's example when one exists).

**Library filename convention**: the rule name with `/` replaced by `--` and a leading `@` stripped; `@typescript-eslint/no-floating-promises` → `typescript-eslint--no-floating-promises.md`, core `eqeqeq` → `eqeqeq.md`, `TS2345` → `TS2345.md`.

## Steps

### 1. Check the example library first

`@references/typescript/rules/<FILENAME>.md` (convention above) is the library: one file per rule, already in the output format. When the file exists, serve it; adapt the wrong snippet to the user's real code when they gave a concrete file, otherwise return it as is. Steps 2–5 are for rules with no library file.

### 2. Establish the rule's intent

Doc URL patterns; the rule name is the key:

- ESLint core: `https://eslint.org/docs/latest/rules/<name>`
- typescript-eslint: `https://typescript-eslint.io/rules/<name>`
- unicorn: `https://github.com/sindresorhus/eslint-plugin-unicorn/blob/main/docs/rules/<name>.md`
- sonarjs: `https://github.com/SonarSource/eslint-plugin-sonarjs/blob/main/docs/rules/<name>.md`
- tsc `TSxxxx`: no per-code doc site; reproduce the error in a scratch file and read the compiler message; it names the incompatible types

Fetch the doc (WebFetch) for the description and its incorrect/correct examples. A fix based on a misremembered intent is worse than none.

### 3. Establish the context

The source of truth is the **target repo's** `eslint.config.js` (overrides per file glob); when the repo has none, fall back to the **Kit config** line each `@references/typescript/rules/` file carries. The main context splits:

- tests: `no-explicit-any` and `no-non-null-assertion` are legitimately off in `*.test.ts`; mocks and fixtures need them
- async rules (`no-floating-promises`, `no-misused-promises`): the fix is `await` (or explicit `void` with a comment naming why fire-and-forget is intended); never a disable comment
- type-escape findings (`any`, `as`, `@ts-expect-error`): the fix narrows types (type predicates, discriminated unions, `unknown` + narrowing), never widens them

If the warning comes from a concrete file, build the wrong snippet from the real code, minimized. Without one, write the canonical example.

### 4. Write the fix in modern TypeScript idioms

- `unknown` over `any`, narrowed by type predicates or discriminated unions
- exhaustive `switch` with a `never` default arm; `satisfies` for config objects
- `import type` for type-only imports (verbatimModuleSyntax-clean)
- promises: `await` everything, `Promise.all` for independent work, `AbortSignal` propagated
- nullish tools: `??`, `?.`, and `noUncheckedIndexedAccess`-safe index access (check before use)
- phrase the principle sentence concretely: "the union has 4 variants and the switch handles 3; the `never` arm turns the missing case into a compile error", not "improves type safety"

### 5. Verify proportionally

Scratch npm project in the scratchpad (once per session): `eslint`, `typescript-eslint`, `@eslint/js`, `typescript` installed, a minimal flat config enabling **only the rule under test** as `error` (type-checked rules need `projectService: true` and a tsconfig). Run `npx eslint snippet.ts`; the wrong snippet must fire, the right one must be silent. tsc snippets: `npx tsc --noEmit snippet.ts` (with the strict flags the finding assumes). A single-token change may skip verification.

### 6. Grow the library

Save the newly written example as `@references/typescript/rules/<FILENAME>.md` in the format the existing library files use (open any one as the template), so the next request for this rule is a lookup, not a rebuild.

## Language-specific Done-when additions

When the finding is legacy debt rather than new code, the freezing techniques to offer are: `npx eslint . --fix --suppress-rule '<rule>'` (bulk suppression into `eslint-suppressions.json`), a per-glob override in `eslint.config.js` for the legacy directory, or (tsc flags) backing the flag out globally with a re-enable plan; tsc has no baseline mechanism.
