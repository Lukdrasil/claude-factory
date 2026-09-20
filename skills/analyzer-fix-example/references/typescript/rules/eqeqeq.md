# eqeqeq: Require `===` and `!==` over `==` and `!=`

**Tool**: ESLint core · **Kit config**: error (kit eslint.config.js; not part of eslint:recommended, set explicitly) · **Docs**: https://eslint.org/docs/latest/rules/eqeqeq

## Wrong

```typescript
export function isMatch(a: string, b: string): boolean {
  return a == b;
}
```

## Right

```typescript
export function isMatch(a: string, b: string): boolean {
  return a === b;
}
```

**Principle**: `==` triggers implicit type coercion before comparing, so values of different types can compare equal in ways the author never intended.
