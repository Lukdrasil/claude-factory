# @typescript-eslint/no-unused-vars: Do not declare a variable that is never read

**Tool**: typescript-eslint · **Kit config**: error via recommended · **Docs**: https://typescript-eslint.io/rules/no-unused-vars/

## Wrong

```typescript
export function run(): number {
  const unused = 42;
  return 1;
}
```

## Right

```typescript
export function run(): number {
  const value = 42;
  return value;
}
```

**Principle**: an unread binding is either dead code or a bug where the intended value was never wired up, and both are worth flagging before merge.
