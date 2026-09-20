# @typescript-eslint/no-unnecessary-condition: Do not test a condition whose type can never be the other branch

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via strictTypeChecked (escalation tier) · **Docs**: https://typescript-eslint.io/rules/no-unnecessary-condition/

## Wrong

```typescript
export function describeList(items: string[]): string {
  if (items) {
    return `has ${items.length} items`;
  }
  return "no items";
}
```

## Right

```typescript
export function describeList(items: string[]): string {
  return `has ${items.length} items`;
}
```

**Principle**: `items` is a non-nullable array type, so the `if` can never be false and the dead "no items" branch hides the real assumption the code depends on.
