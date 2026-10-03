# .NET reference

```csharp
public readonly record struct ContractId(Guid Value)
{
    public static ContractId New() => new(Guid.CreateVersion7());
}

public sealed class Contract
{
    public ContractId Id { get; private set; }
    public DateRange Window { get; private set; }

    private Contract() { }

    public static Result<Contract> Create(DateRange window, ...) { ... }
    public Result Extend(DateOnly newEnd) { ... }
}
```

- The repo's own `Result` type, never a new one.
- EF value converters for typed ids live in the infrastructure project's entity configuration.
- A predicate is a method on the aggregate or a static member of one type, never a copied lambda.
