---
name: blazor-server
description: Blazor Server and FluentUI v5 rules for circuit lifetime, user identity, state across reconnects, culture and styling. Use when writing a .razor component or its code-behind in a Blazor Server app.
---

# Blazor Server and FluentUI v5

A Blazor Server component lives in a **circuit** that outlasts the HTTP request that opened it, survives
reconnects and runs on its own synchronization context.

## Rules

1. **`HttpContext` exists only during the first render.** After it, identity comes from
   `AuthenticationStateProvider` or a cascaded `Task<AuthenticationState>`.
2. **State that must survive prerendering or a reconnect is persisted explicitly** with
   `PersistentComponentState`, or `[PersistentState]` on .NET 10.
3. **Enumerables captured by a callback or render fragment are materialized** (`ToList()`) before capture.
4. **Culture is set explicitly where a `RenderFragment` or `ChildContent` renders**, because it does not flow
   from the parent automatically.
5. **UI text lives in `.resx`** and is read through `IStringLocalizer<T>`.
6. **Inspect the rendered DOM before styling a FluentUI v5 component**: it is a web component with shadow
   parts. Style through its documented parts and design tokens. Look up the component API through the
   `fluent-ui-blazor` MCP server when it is available.

## Steps

1. **List every component** the change adds or edits and what it reads from the request, state and culture.
   Done when none is missing.
2. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- `HttpContext.User` was read after a reconnect and was null. Right: `AuthenticationStateProvider`.
- Culture did not reach `ChildContent`. Right: set it where the fragment renders.
