# @typescript-eslint/no-base-to-string: Do not stringify a type whose `toString()` is the useless default

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/no-base-to-string/

## Wrong

```typescript
class Point {
  constructor(
    public x: number,
    public y: number,
  ) {}
}

export function describe(point: Point): string {
  return `Point: ${point}`;
}
```

## Right

```typescript
class Point {
  constructor(
    public x: number,
    public y: number,
  ) {}

  toString(): string {
    return `(${this.x}, ${this.y})`;
  }
}

export function describe(point: Point): string {
  return "Point: " + point.toString();
}
```

**Principle**: without a custom `toString`, `Point` stringifies to the meaningless `"[object Object]"`, so the fix has to give the class an actual textual representation, not just silence the lint.
