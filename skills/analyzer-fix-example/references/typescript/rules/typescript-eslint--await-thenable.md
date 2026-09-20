# @typescript-eslint/await-thenable: Do not `await` a value that is not a Promise

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/await-thenable/

## Wrong

```typescript
export function getValue(): number {
  return 42;
}

export async function run(): Promise<number> {
  return await getValue();
}
```

## Right

```typescript
export function getValue(): number {
  return 42;
}

export function run(): number {
  return getValue();
}
```

**Principle**: awaiting a non-Promise value adds a needless microtask tick and hides that the function was never asynchronous to begin with.
