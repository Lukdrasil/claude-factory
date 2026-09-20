# @typescript-eslint/consistent-type-imports: Import types with `import type`

**Tool**: typescript-eslint · **Kit config**: error (kit eslint.config.js; not part of any preset config, set explicitly) · **Docs**: https://typescript-eslint.io/rules/consistent-type-imports/

## Wrong

```typescript
import { Widget } from "./helpers/types";

export function describe(widget: Widget): string {
  return widget.label;
}
```

## Right

```typescript
import type { Widget } from "./helpers/types";

export function describe(widget: Widget): string {
  return widget.label;
}
```

**Principle**: a value import of a type-only binding can survive into the compiled output as a dead runtime import, and it hides from readers that `Widget` never exists at runtime.
