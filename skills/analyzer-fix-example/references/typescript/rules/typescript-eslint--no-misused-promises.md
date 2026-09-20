# @typescript-eslint/no-misused-promises: Promise-returning functions must not be used where a void return is expected

**Tool**: typescript-eslint (type-checked) · **Kit config**: error (kit eslint.config.js) · **Docs**: https://typescript-eslint.io/rules/no-misused-promises/

## Wrong

```typescript
async function save(item: string): Promise<void> {
  await Promise.resolve(item);
}

export function saveAll(items: string[]): void {
  items.forEach(async (item) => {
    await save(item);
  });
}
```

## Right

```typescript
async function save(item: string): Promise<void> {
  await Promise.resolve(item);
}

export async function saveAll(items: string[]): Promise<void> {
  for (const item of items) {
    await save(item);
  }
}
```

**Principle**: `Array.prototype.forEach` never awaits its callback, so an async callback's rejections and ordering guarantees are silently discarded.
