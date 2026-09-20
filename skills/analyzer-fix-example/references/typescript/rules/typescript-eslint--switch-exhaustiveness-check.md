# @typescript-eslint/switch-exhaustiveness-check: A `switch` over a union must handle every member

**Tool**: typescript-eslint (type-checked) · **Kit config**: error (kit eslint.config.js; not part of any preset config, set explicitly) · **Docs**: https://typescript-eslint.io/rules/switch-exhaustiveness-check/

## Wrong

```typescript
type Status = "pending" | "done" | "failed";

export function describeStatus(status: Status): string {
  switch (status) {
    case "pending":
      return "Pending";
    case "done":
      return "Done";
  }
  return "Unknown";
}
```

## Right

```typescript
type Status = "pending" | "done" | "failed";

export function describeStatus(status: Status): string {
  switch (status) {
    case "pending":
      return "Pending";
    case "done":
      return "Done";
    case "failed":
      return "Failed";
    default: {
      const exhaustiveCheck: never = status;
      return exhaustiveCheck;
    }
  }
}
```

**Principle**: a missing case for `"failed"` compiles fine today but silently falls through to the wrong behavior the moment that value shows up at runtime; the `never` arm turns a future added union member into a compile error instead.
