# .NET reference

## Grammar

```csharp
[GeneratedRegex("^[a-z0-9][a-z0-9-]{2,62}$")]
private static partial Regex ClientIdGrammar();
```

Parse into a typed id at the edge (`ClientId.TryParse`) so code behind the edge cannot hold an unchecked
string.

## Identity

- `user.FindFirst(claimType)` returning null is `Results.Unauthorized()`, never `?? "default"`.
- Resource checks go through `IAuthorizationService.AuthorizeAsync(user, resource, policy)` or one
  authorization handler per resource type, so every route reaches the same check.
- Return `Results.NotFound()` for both "absent" and "not yours" where existence is itself sensitive.

## Response text

ProblemDetails `detail` is a fixed string per error code. Exceptions and upstream bodies go to the log,
through the redaction rules in `logging-decisions`.
