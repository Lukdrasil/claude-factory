# @typescript-eslint/no-explicit-any: Do not use the `any` type

**Tool**: typescript-eslint · **Kit config**: error via recommended; off in *.test.ts (kit override) · **Docs**: https://typescript-eslint.io/rules/no-explicit-any/

## Wrong

```typescript
export function parseValue(input: any): string {
  return input.toString();
}
```

## Right

```typescript
export function parseValue(input: unknown): string {
  if (typeof input === "string") {
    return input;
  }
  return String(input);
}
```

**Principle**: `any` disables the type checker entirely on that value, so every later mistake with it goes undetected until it fails at runtime.
