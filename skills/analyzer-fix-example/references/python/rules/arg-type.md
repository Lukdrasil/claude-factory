# arg-type: argument-type-mismatch

**Tool**: mypy (code `[arg-type]`) · **Docs**: https://mypy.readthedocs.io/en/stable/error_code_list.html

## Wrong

```python
def greet(name: str) -> str:
    return f"Hello, {name}"


def main() -> None:
    print(greet(42))
```

## Right

```python
def greet(name: str) -> str:
    return f"Hello, {name}"


def main() -> None:
    print(greet("42"))
```

**Principle**: passing an `int` where a `str` is declared breaks the function's contract at the call site; fixing the call keeps the declared signature trustworthy for every other caller.
