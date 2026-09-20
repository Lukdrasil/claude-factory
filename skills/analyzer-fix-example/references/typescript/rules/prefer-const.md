# prefer-const: Use `const` for variables that are never reassigned

**Tool**: ESLint core · **Kit config**: error (kit eslint.config.js; not part of eslint:recommended, set explicitly) · **Docs**: https://eslint.org/docs/latest/rules/prefer-const

## Wrong

```typescript
export function double(value: number): number {
  let result = value * 2;
  return result;
}
```

## Right

```typescript
export function double(value: number): number {
  const result = value * 2;
  return result;
}
```

**Principle**: declaring `result` with `let` when it is never reassigned invites a future edit to mutate it by accident; `const` makes that impossible at compile time.
