# @typescript-eslint/no-unsafe-assignment: Do not assign an `any` value to a typed variable

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/no-unsafe-assignment/

## Wrong

```typescript
function getData(): any {
  return { id: 1 };
}

export function run(): { id: number } {
  const data: { id: number } = getData();
  return data;
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

export function run(): Data {
  const data = getData();
  return data;
}
```

**Principle**: assigning `any` into a typed slot launders an unchecked value through the type system, so the annotation stops meaning anything from that point on.
