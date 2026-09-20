# Debt freezing; TypeScript/JavaScript

## Technique A; ESLint bulk suppressions (native, ESLint >= 9.24)

One-time freeze of all existing findings into `eslint-suppressions.json`:

```bash
npx eslint . --fix --suppress-all
```

Commit the file. CI then runs plain `eslint .`; suppressed findings stay silent, a **new** finding fails. Enabling one new rule on a legacy codebase: `npx eslint . --fix --suppress-rule '@typescript-eslint/no-floating-promises'`.

Paydown: after fixes run `npx eslint . --prune-suppressions` (removes unused entries). In CI add `--pass-on-unpruned-suppressions`, otherwise paid-down debt fails the build over a stale entry.

Debt metric: the number of entries in `eslint-suppressions.json`.

## Technique B; type-checking debt (tsc)

`tsc` has no baseline. Tighten flag by flag: enable a new flag (`noUncheckedIndexedAccess`...), count the errors; hundreds of errors → back the flag out and record it as debt, singles to tens → fix now. For a visible trend: **Betterer** (a ratchet over tsc/ESLint; fails only when the numbers get worse).

## Technique C; dead code (knip)

`npx knip --no-exit-code` = report-only mode until the entry-point config is tuned; then switch to the hard gate without the flag.

## Paydown rule

Every freeze gets an issue with a deadline. A suppressions file without a paydown plan is just a slower way to disable the rules.
