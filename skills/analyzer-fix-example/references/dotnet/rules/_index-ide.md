# IDE rules index (.NET code-style rules)

Source: [Code-style rules overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/index).

Doc URL pattern: `https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/<doc-slug>` (slug is usually the lowercase ID, e.g. `ide0001`; a few rules share one doc page covering several IDs, e.g. `ide0003-ide0009`, `ide0007-ide0008`; the slug used for each row is given in the link).

Code-style analysis is *off* by default on command-line/CI builds (`EnforceCodeStyleInBuild` must be set to `true` to run IDE rules at build time); inside Visual Studio these rules run live as refactoring suggestions regardless. There is no per-rule "enabled by default" table for IDE rules the way there is for CA rules.

| ID | Title |
| --- | --- |
| [IDE0001](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0001) | Simplify name |
| [IDE0002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0002) | Simplify member access |
| [IDE0003](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0003-ide0009) | Name can be simplified |
| [IDE0004](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0004) | Remove unnecessary cast |
| [IDE0005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0005) | Remove unnecessary import |
| [IDE0007](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0007-ide0008) | Use `var` instead of explicit type |
| [IDE0008](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0007-ide0008) | Use explicit type instead of `var` |
| [IDE0009](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0003-ide0009) | Member access should be qualified |
| [IDE0010](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0010) | Add missing cases to switch statement |
| [IDE0011](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0011) | Add braces |
| [IDE0016](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0016) | Use throw expression |
| [IDE0017](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0017) | Use object initializers |
| [IDE0018](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0018) | Inline variable declaration |
| [IDE0019](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0019) | Use pattern matching to avoid `as` followed by a `null` check |
| [IDE0020](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0020-ide0038) | Use pattern matching to avoid `is` check followed by a cast (with variable) |
| [IDE0021](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0021) | Use expression body for constructors |
| [IDE0022](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0022) | Use expression body for methods |
| [IDE0023](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0023-ide0024) | Use expression body for conversion operators |
| [IDE0024](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0023-ide0024) | Use expression body for operators |
| [IDE0025](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0025) | Use expression body for properties |
| [IDE0026](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0026) | Use expression body for indexers |
| [IDE0027](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0027) | Use expression body for accessors |
| [IDE0028](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0028) | Use collection initializers |
| [IDE0029](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0029-ide0030-ide0270) | Null check can be simplified |
| [IDE0030](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0029-ide0030-ide0270) | Null check can be simplified |
| [IDE0031](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0031) | Use null propagation |
| [IDE0032](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0032) | Use auto property |
| [IDE0033](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0033) | Use explicitly provided tuple name |
| [IDE0034](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0034) | Simplify `default` expression |
| [IDE0035](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0035) | Remove unreachable code |
| [IDE0036](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0036) | Order modifiers |
| [IDE0037](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0037) | Use inferred member name |
| [IDE0038](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0020-ide0038) | Use pattern matching to avoid `is` check followed by a cast (without variable) |
| [IDE0039](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0039) | Use local function instead of lambda |
| [IDE0040](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0040) | Add accessibility modifiers |
| [IDE0041](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0041) | Use is null check |
| [IDE0042](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0042) | Deconstruct variable declaration |
| [IDE0043](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0043) | Invalid format string |
| [IDE0044](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0044) | Add readonly modifier |
| [IDE0045](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0045) | Use conditional expression for assignment |
| [IDE0046](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0046) | Use conditional expression for return |
| [IDE0047](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0047-ide0048) | Remove unnecessary parentheses |
| [IDE0048](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0047-ide0048) | Add parentheses for clarity |
| [IDE0049](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0049) | Use language keywords instead of framework type names for type references |
| [IDE0050](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0050) | Convert anonymous type to tuple |
| [IDE0051](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0051) | Remove unused private member |
| [IDE0052](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0052) | Remove unread private member |
| [IDE0053](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0053) | Use expression body for lambdas |
| [IDE0054](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0054-ide0074) | Use compound assignment |
| [IDE0055](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0055) | Fix formatting |
| [IDE0056](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0056) | Use index operator |
| [IDE0057](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0057) | Use range operator |
| [IDE0058](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0058) | Remove unused expression value |
| [IDE0059](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0059) | Remove unnecessary value assignment |
| [IDE0060](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0060) | Remove unused parameter |
| [IDE0061](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0061) | Use expression body for local functions |
| [IDE0062](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0062) | Make local function `static` |
| [IDE0063](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0063) | Use simple `using` statement |
| [IDE0064](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0064) | Make struct fields writable |
| [IDE0065](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0065) | `using` directive placement |
| [IDE0066](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0066) | Use switch expression |
| [IDE0070](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0070) | Use System.HashCode.Combine |
| [IDE0071](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0071) | Simplify interpolation |
| [IDE0072](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0072) | Add missing cases to switch expression |
| [IDE0073](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0073) | Use file header |
| [IDE0074](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0054-ide0074) | Use coalesce compound assignment |
| [IDE0075](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0075) | Simplify conditional expression |
| [IDE0076](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0076) | Remove invalid global `SuppressMessageAttribute` |
| [IDE0077](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0077) | Avoid legacy format target in global `SuppressMessageAttribute` |
| [IDE0078](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0078-ide0260) | Use pattern matching |
| [IDE0079](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0079) | Remove unnecessary suppression |
| [IDE0080](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0080) | Remove unnecessary suppression operator |
| [IDE0081](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0081) | Remove `ByVal` |
| [IDE0082](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0082) | Convert `typeof` to `nameof` |
| [IDE0083](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0083) | Use pattern matching (`not` operator) |
| [IDE0084](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0084) | Use pattern matching (`IsNot` operator) |
| [IDE0090](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0090) | Simplify `new` expression |
| [IDE0100](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0100) | Remove unnecessary equality operator |
| [IDE0110](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0110) | Remove unnecessary discard |
| [IDE0120](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0120) | Simplify LINQ expression |
| [IDE0121](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0121) | Simplify LINQ type check and cast |
| [IDE0130](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0130) | Namespace does not match folder structure |
| [IDE0140](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0140) | Simplify object creation |
| [IDE0150](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0150) | Prefer `null` check over type check |
| [IDE0160](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0160-ide0161) | Use block-scoped namespace |
| [IDE0161](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0160-ide0161) | Use file-scoped namespace |
| [IDE0170](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0170) | Simplify property pattern |
| [IDE0180](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0180) | Use tuple to swap values |
| [IDE0200](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0200) | Remove unnecessary lambda expression |
| [IDE0210](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0210) | Convert to top-level statements |
| [IDE0211](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0211) | Convert to 'Program.Main' style program |
| [IDE0220](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0220) | Add explicit cast in foreach loop |
| [IDE0221](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0221) | Add explicit cast |
| [IDE0230](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0230) | Use UTF-8 string literal |
| [IDE0240](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0240) | Nullable directive is redundant |
| [IDE0241](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0241) | Nullable directive is unnecessary |
| [IDE0250](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0250) | Struct can be made 'readonly' |
| [IDE0251](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0251) | Member can be made 'readonly' |
| [IDE0260](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0078-ide0260) | Use pattern matching |
| [IDE0270](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0029-ide0030-ide0270) | Null check can be simplified |
| [IDE0280](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0280) | Use `nameof` |
| [IDE0290](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0290) | Use primary constructor |
| [IDE0300](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0300) | Use collection expression for array |
| [IDE0301](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0301) | Use collection expression for empty |
| [IDE0302](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0302) | Use collection expression for stackalloc |
| [IDE0303](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0303) | Use collection expression for `Create()` |
| [IDE0304](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0304) | Use collection expression for builder |
| [IDE0305](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0305) | Use collection expression for fluent |
| [IDE0306](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0306) | Use collection expression for new |
| [IDE0320](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0320) | Make anonymous function `static` |
| [IDE0330](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0330) | Prefer 'System.Threading.Lock' |
| [IDE0340](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0340) | Use unbound generic type |
| [IDE0350](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0350) | Use implicitly typed lambda |
| [IDE0360](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0360) | Simplify property accessor |
| [IDE0370](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0370) | Remove unnecessary suppression |
| [IDE0380](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0380) | Remove unnecessary 'unsafe' modifier |
| [IDE0390](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0390-ide0391) | Make method synchronous |
| [IDE0391](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0390-ide0391) | Make method synchronous |
| [IDE0410](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide0410) | Use labeled jump statement |
| [IDE1005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide1005) | Use conditional delegate call |
| [IDE1006](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/naming-rules) | Naming styles |
| [IDE1007](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide1007) | The name does not exist in the current context |
| [IDE2000](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2000) | Avoid multiple blank lines |
| [IDE2001](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2001) | Embedded statements must be on their own line |
| [IDE2002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2002) | Consecutive braces must not have blank line between them |
| [IDE2003](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2003) | Blank line required between block and subsequent statement |
| [IDE2004](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2004) | Blank line not allowed after constructor initializer colon |
| [IDE2005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2005) | Blank line not allowed after conditional expression token |
| [IDE2006](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide2006) | Blank line not allowed after arrow expression clause token |
| [IDE3000](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/style-rules/ide3000) | Implement with Copilot |

