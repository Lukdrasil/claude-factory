# reportOptionalMemberAccess: optional-member-access

**Tool**: pyright · **Docs**: https://microsoft.github.io/pyright/#/configuration

## Wrong

```python
from dataclasses import dataclass


@dataclass
class User:
    name: str
    manager: "User | None" = None


def manager_name(user: User) -> str:
    return user.manager.name
```

## Right

```python
from dataclasses import dataclass


@dataclass
class User:
    name: str
    manager: "User | None" = None


def manager_name(user: User) -> str:
    if user.manager is None:
        raise ValueError("user has no manager")
    return user.manager.name
```

**Principle**: narrowing the Optional with an explicit check before use converts a possible `AttributeError` at runtime into a compile-time-verified guarantee that `.name` is only accessed when the manager exists.
