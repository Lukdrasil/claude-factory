# .NET reference

## Required members

`required` does not apply to positional record parameters. Mark them for the serializer:

```csharp
public sealed record CreateToken(
    [property: JsonRequired] string Name,
    [property: JsonRequired] DateTimeOffset ExpiresAt);
```

On .NET 9 and later, `JsonSerializerOptions.RespectNullableAnnotations` and
`RespectRequiredConstructorParameters` make the serializer enforce the declared shape.

## Enums

`new JsonStringEnumConverter(allowIntegerValues: false)` in the HTTP JSON options.

## Validation and errors

- Minimal APIs on .NET 10: `builder.Services.AddValidation()` validates bound parameters before the handler.
  Earlier versions or other validators: an endpoint filter on the route group.
- `AddProblemDetails()` plus one `IExceptionHandler` and one `DomainError -> status` switch.
- A `BadHttpRequestException` from binding maps to 400 through `RouteHandlerOptions.ThrowOnBadRequest` off
  (the default) or the exception handler.

## Claims

`JwtBearerOptions.MapInboundClaims` changes claim type names (`sub` vs `ClaimTypes.NameIdentifier`). Flipping
it requires a search of every `FindFirst`, policy and claim check.

## OpenAPI diff

Generate the document at build time (`Microsoft.Extensions.ApiDescription.Server`) and compare it with the
base branch's document before merging a contract change.
