# @typescript-eslint/require-await: An `async` function must contain an `await`

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/require-await/

## Wrong

```typescript
export async function readConfig(): Promise<string> {
  return "config";
}
```

## Right

```typescript
export function readConfig(): string {
  return "config";
}
```

**Principle**: an `async` function with no `await` wraps its result in a needless Promise and misleads callers into thinking real asynchronous work happens.
