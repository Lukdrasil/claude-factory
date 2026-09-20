# @typescript-eslint/restrict-template-expressions: Only interpolate primitive-safe values into template literals

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/restrict-template-expressions/

## Wrong

```typescript
export function describe(value: object): string {
  return `Value: ${value}`;
}
```

## Right

```typescript
export function describe(value: object): string {
  return `Value: ${JSON.stringify(value)}`;
}
```

**Principle**: interpolating a plain object falls back to `Object.prototype.toString`, producing the useless literal string `"[object Object]"` instead of the data the caller actually wanted.
