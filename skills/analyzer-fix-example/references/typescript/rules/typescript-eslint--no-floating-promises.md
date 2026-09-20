# @typescript-eslint/no-floating-promises: Promises must be awaited or explicitly handled

**Tool**: typescript-eslint (type-checked) · **Kit config**: error (kit eslint.config.js) · **Docs**: https://typescript-eslint.io/rules/no-floating-promises/

## Wrong

```typescript
async function loadUser(id: string): Promise<{ id: string; name: string }> {
  await Promise.resolve();
  return { id, name: "Ada" };
}

export function handleClick(): void {
  loadUser("42");
}
```

## Right

```typescript
async function loadUser(id: string): Promise<{ id: string; name: string }> {
  await Promise.resolve();
  return { id, name: "Ada" };
}

export async function handleClick(): Promise<void> {
  await loadUser("42");
}
```

**Principle**: an unawaited promise swallows its rejection and the failure surfaces nowhere.
