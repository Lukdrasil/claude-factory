# Coding skills

Read the skill for each thing the change touches, at `<plugin-root>/skills/<skill>/SKILL.md`, and apply
every rule it lists. A review finding against one names the skill and the rule number, such as
`fail-closed 3`.

| The change touches | Skill |
|---|---|
| a test | `falsifiable-tests` |
| a catch, a returned result, a background loop, cancellation, a lock | `fail-closed` |
| a log call | `logging-decisions` |
| a `DbContext`, repository, entity configuration or read query | `ef-core-persistence` |
| external input reaching a path, key, URL, query, authorization or response | `trust-boundary` |
| an endpoint, a request or response DTO, an error-to-status mapping | `api-contract` |
| an entity, aggregate, value object or business rule | `domain-invariants` |
| the clock, a date, a duration, a date format | `time-and-dates` |
| a message handler, workflow step, retry or create endpoint | `idempotency` |
| an outbound HTTP call or client registration | `outbound-http` |
| service registration, options, a hosted service, startup | `composition-root` |
| a new type, file, project reference or cross-module call | `architecture-rules` |
| a `.razor` component in a Blazor Server app | `blazor-server` |
| any new helper or shared type, and every change before it is done | `reuse-first` |
