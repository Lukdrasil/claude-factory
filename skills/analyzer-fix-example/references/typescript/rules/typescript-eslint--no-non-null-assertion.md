# @typescript-eslint/no-non-null-assertion: Do not use the `!` non-null assertion operator

**Tool**: typescript-eslint · **Kit config**: error via strict (escalation tier); off in *.test.ts (kit override) · **Docs**: https://typescript-eslint.io/rules/no-non-null-assertion/

## Wrong

```typescript
export function getLength(value: string | undefined): number {
  return value!.length;
}
```

## Right

```typescript
export function getLength(value: string | undefined): number {
  return value?.length ?? 0;
}
```

**Principle**: `!` tells the compiler to trust a claim it cannot verify, so when the value actually is `undefined` the crash happens at the access site with no compile-time warning.
