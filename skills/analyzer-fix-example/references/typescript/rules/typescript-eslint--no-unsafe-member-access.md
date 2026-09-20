# @typescript-eslint/no-unsafe-member-access: Do not access a member on an `any` value

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/no-unsafe-member-access/

## Wrong

```typescript
function getData(): any {
  return { id: 1 };
}

export function run(): number {
  const data = getData();
  return data.id;
}
```

## Right

```typescript
interface Data {
  id: number;
}

function getData(): Data {
  return { id: 1 };
}

export function run(): number {
  const data = getData();
  return data.id;
}
```

**Principle**: `data.id` on an `any` value is not checked to exist, so a typo or a shape change surfaces as `undefined` at runtime instead of a compile error.
