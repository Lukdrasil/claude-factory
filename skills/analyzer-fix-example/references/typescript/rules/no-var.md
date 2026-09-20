# no-var: Use `let`/`const` instead of `var`

**Tool**: ESLint core · **Kit config**: error (kit eslint.config.js; not part of eslint:recommended, set explicitly) · **Docs**: https://eslint.org/docs/latest/rules/no-var

## Wrong

```typescript
export function sum(values: number[]): number {
  var total = 0;
  for (const value of values) {
    total += value;
  }
  return total;
}
```

## Right

```typescript
export function sum(values: number[]): number {
  let total = 0;
  for (const value of values) {
    total += value;
  }
  return total;
}
```

**Principle**: `var` is function-scoped and hoisted, so `total` would remain visible and reassignable outside the loop it was meant to be local to; `let` confines it to the block.
