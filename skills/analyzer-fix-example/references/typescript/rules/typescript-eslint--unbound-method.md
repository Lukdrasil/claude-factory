# @typescript-eslint/unbound-method: Do not reference a class method as a standalone value

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via recommendedTypeChecked · **Docs**: https://typescript-eslint.io/rules/unbound-method/

## Wrong

```typescript
class Counter {
  count = 0;

  increment(): void {
    this.count += 1;
  }
}

export function run(counter: Counter): () => void {
  return counter.increment;
}
```

## Right

```typescript
class Counter {
  count = 0;

  increment(): void {
    this.count += 1;
  }
}

export function run(counter: Counter): () => void {
  return () => {
    counter.increment();
  };
}
```

**Principle**: extracting `counter.increment` detaches the method from its `this`, so calling the returned reference later throws or silently mutates the wrong object.
