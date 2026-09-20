# @typescript-eslint/only-throw-error: Only throw `Error` instances

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/only-throw-error/

## Wrong

```typescript
export function validate(value: number): void {
  if (value < 0) {
    throw "value must be non-negative";
  }
}
```

## Right

```typescript
export function validate(value: number): void {
  if (value < 0) {
    throw new Error("value must be non-negative");
  }
}
```

**Principle**: a thrown string has no stack trace, so a `catch (err)` block downstream loses exactly the information needed to locate where the failure originated.
