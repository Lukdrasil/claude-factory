// Installed at the target repo root as eslint.config.js (ESLint 10; flat config
// is the only supported format, .eslintrc no longer exists).
// Verified versions: eslint 10.8.1, typescript-eslint 8.67.0, @eslint/js 10.0.1.
// Escalation path: recommendedTypeChecked → strictTypeChecked (once the team handles TS well).
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';

export default defineConfig(
  // The config file itself and build output stay out of type-checked linting;
  // projectService errors on files the tsconfig does not include.
  { ignores: ['dist', 'coverage', 'eslint.config.js', 'eslint.config.mjs'] },
  {
    files: ['**/*.{js,ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommendedTypeChecked,
      tseslint.configs.stylisticTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        // projectService asks the TS language service per file;
        // replaces hand-maintained parserOptions.project globs.
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // Unawaited promises are the most expensive bug class in a TS backend.
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      // High value, low noise; in no preset, hence explicit.
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      eqeqeq: 'error',
      'no-var': 'error',
      'prefer-const': 'error',
    },
  },
  {
    // Tests: looser; mocks and fixtures legitimately use any/non-null.
    files: ['**/*.{test,spec}.{ts,tsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
  // Optional plugins; add per repo needs (versions verified 2026-08):
  //   eslint-plugin-unicorn 73.x; general modern JS patterns
  //   eslint-plugin-import-x 4.x; import hygiene (fork of the stagnant eslint-plugin-import)
  //   eslint-plugin-sonarjs 4.x; bug patterns, cognitive complexity
  //   eslint-plugin-boundaries 7.x; architecture boundaries between layers
  //   eslint-config-prettier 10.x; turns off stylistic rules that clash with the formatter
);
