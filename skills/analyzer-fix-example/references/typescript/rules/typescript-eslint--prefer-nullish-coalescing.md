# @typescript-eslint/prefer-nullish-coalescing: Prefer `??` over `||` for default values

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via stylisticTypeChecked · **Docs**: https://typescript-eslint.io/rules/prefer-nullish-coalescing/

## Wrong

```typescript
export function getName(name: string | undefined): string {
  return name || "Anonymous";
}
```

## Right

```typescript
export function getName(name: string | undefined): string {
  return name ?? "Anonymous";
}
```

**Principle**: `||` falls back on every falsy value, so a valid empty string gets silently replaced by the default instead of only `null`/`undefined` triggering it.
