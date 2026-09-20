# @typescript-eslint/prefer-optional-chain: Prefer `?.` over manual `&&` guard chains

**Tool**: typescript-eslint (type-checked) · **Kit config**: error via stylisticTypeChecked · **Docs**: https://typescript-eslint.io/rules/prefer-optional-chain/

## Wrong

```typescript
interface Address {
  city?: string;
}

interface User {
  address?: Address;
}

export function getCity(user: User): string | undefined {
  return user.address && user.address.city;
}
```

## Right

```typescript
interface Address {
  city?: string;
}

interface User {
  address?: Address;
}

export function getCity(user: User): string | undefined {
  return user.address?.city;
}
```

**Principle**: a manual `&&` chain re-evaluates and repeats each intermediate property access, growing error-prone as the chain deepens, where `?.` expresses the same short-circuit in one pass.
