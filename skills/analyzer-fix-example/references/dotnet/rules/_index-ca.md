# CA rules index (.NET code-quality rules)

Source: [Code quality rules overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/index) and [dotnet/roslyn-analyzers AnalyzerReleases.Shipped.md](https://github.com/dotnet/roslyn-analyzers/blob/main/src/NetAnalyzers/Core/AnalyzerReleases.Shipped.md).

Doc URL pattern: `https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/<id-lowercase>`

"Enabled by default" = Yes means the rule ships as a build **Warning** or **Error** in the default (`Default`) analysis mode on the latest .NET SDK. Rules marked No are `Disabled`/`Info`/`Hidden` by default (they show only as an IDE suggestion, or not at all) unless you raise `<AnalysisMode>` to `Minimum`, `Recommended`, or `All` in the project file. See [Code analysis overview](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview) for the `AnalysisMode` levels; the exact rule set for `Recommended`/`All` is generated per SDK version into `analysislevel_<level>_recommended.globalconfig` and isn't published as a single web page, so it isn't reproduced row-by-row here.

| ID | Title | Category | Enabled by default |
| --- | --- | --- | --- |
| [CA1000](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1000) | Do not declare static members on generic types | Design | No |
| [CA1001](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1001) | Types that own disposable fields should be disposable | Design | No |
| [CA1002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1002) | Do not expose generic lists | Design | No |
| [CA1003](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1003) | Use generic event handler instances | Design | No |
| [CA1005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1005) | Avoid excessive parameters on generic types | Design | No |
| [CA1008](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1008) | Enums should have zero value | Design | No |
| [CA1010](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1010) | Collections should implement generic interface | Design | No |
| [CA1012](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1012) | Abstract types should not have public constructors | Design | No |
| [CA1014](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1014) | Mark assemblies with CLSCompliantAttribute | Design | No |
| [CA1016](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1016) | Mark assemblies with AssemblyVersionAttribute | Design | No |
| [CA1017](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1017) | Mark assemblies with ComVisibleAttribute | Design | No |
| [CA1018](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1018) | Mark attributes with AttributeUsageAttribute | Design | No |
| [CA1019](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1019) | Define accessors for attribute arguments | Design | No |
| [CA1021](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1021) | Avoid out parameters | Design | No |
| [CA1024](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1024) | Use properties where appropriate | Design | No |
| [CA1027](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1027) | Mark enums with FlagsAttribute | Design | No |
| [CA1028](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1028) | Enum storage should be Int32 | Design | No |
| [CA1030](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1030) | Use events where appropriate | Design | No |
| [CA1031](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1031) | Do not catch general exception types | Design | No |
| [CA1032](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1032) | Implement standard exception constructors | Design | No |
| [CA1033](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1033) | Interface methods should be callable by child types | Design | No |
| [CA1034](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1034) | Nested types should not be visible | Design | No |
| [CA1036](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1036) | Override methods on comparable types | Design | No |
| [CA1040](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1040) | Avoid empty interfaces | Design | No |
| [CA1041](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1041) | Provide ObsoleteAttribute message | Design | No |
| [CA1043](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1043) | Use integral or string argument for indexers | Design | No |
| [CA1044](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1044) | Properties should not be write only | Design | No |
| [CA1045](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1045) | Do not pass types by reference | Design | No |
| [CA1046](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1046) | Do not overload operator equals on reference types | Design | No |
| [CA1047](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1047) | Do not declare protected members in sealed types | Design | No |
| [CA1050](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1050) | Declare types in namespaces | Design | No |
| [CA1051](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1051) | Do not declare visible instance fields | Design | No |
| [CA1052](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1052) | Static holder types should be sealed | Design | No |
| [CA1053](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1053) | Static holder types should not have constructors | Design | No |
| [CA1054](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1054) | URI parameters should not be strings | Design | No |
| [CA1055](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1055) | URI return values should not be strings | Design | No |
| [CA1056](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1056) | URI properties should not be strings | Design | No |
| [CA1058](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1058) | Types should not extend certain base types | Design | No |
| [CA1060](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1060) | Move P/Invokes to NativeMethods class | Design | No |
| [CA1061](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1061) | Do not hide base class methods | Design | No |
| [CA1062](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1062) | Validate arguments of public methods | Design | No |
| [CA1063](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1063) | Implement IDisposable correctly | Design | No |
| [CA1064](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1064) | Exceptions should be public | Design | No |
| [CA1065](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1065) | Do not raise exceptions in unexpected locations | Design | No |
| [CA1066](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1066) | Implement IEquatable when overriding Equals | Design | No |
| [CA1067](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1067) | Override Equals when implementing IEquatable | Design | No |
| [CA1068](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1068) | CancellationToken parameters must come last | Design | No |
| [CA1069](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1069) | Enums should not have duplicate values | Design | No |
| [CA1070](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1070) | Do not declare event fields as virtual | Design | No |
| [CA1200](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1200) | Avoid using cref tags with a prefix | Documentation | No |
| [CA1303](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1303) | Do not pass literals as localized parameters | Globalization | No |
| [CA1304](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1304) | Specify CultureInfo | Globalization | No |
| [CA1305](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1305) | Specify IFormatProvider | Globalization | No |
| [CA1307](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1307) | Specify StringComparison for clarity | Globalization | No |
| [CA1308](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1308) | Normalize strings to uppercase | Globalization | No |
| [CA1309](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1309) | Use ordinal StringComparison | Globalization | No |
| [CA1310](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1310) | Specify StringComparison for correctness | Globalization | No |
| [CA1311](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1311) | Specify a culture or use an invariant version | Globalization | No |
| [CA1401](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1401) | P/Invokes should not be visible | Interoperability | No |
| [CA1416](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1416) | Validate platform compatibility | Interoperability | Yes |
| [CA1417](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1417) | Do not use `OutAttribute` on string parameters for P/Invokes | Interoperability | Yes |
| [CA1418](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1418) | Use valid platform string | Interoperability | Yes |
| [CA1419](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1419) | Provide a parameterless constructor that is as visible as the containing type for concrete types derived from `System.Runtime.InteropServices.SafeHandle` | Interoperability | No |
| [CA1420](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1420) | Property, type, or attribute requires runtime marshalling | Interoperability | Yes |
| [CA1421](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1421) | Method uses runtime marshalling when DisableRuntimeMarshallingAttribute is applied | Interoperability | No |
| [CA1422](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1422) | Validate platform compatibility | Interoperability | Yes |
| [CA1501](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1501) | Avoid excessive inheritance | Maintainability | No |
| [CA1502](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1502) | Avoid excessive complexity | Maintainability | No |
| [CA1505](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1505) | Avoid unmaintainable code | Maintainability | No |
| [CA1506](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1506) | Avoid excessive class coupling | Maintainability | No |
| [CA1507](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1507) | Use nameof in place of string | Maintainability | No |
| [CA1508](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1508) | Avoid dead conditional code | Maintainability | No |
| [CA1509](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1509) | Invalid entry in code metrics configuration file | Maintainability | No |
| [CA1510](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1510) | Use ArgumentNullException throw helper | Maintainability | No |
| [CA1511](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1511) | Use ArgumentException throw helper | Maintainability | No |
| [CA1512](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1512) | Use ArgumentOutOfRangeException throw helper | Maintainability | No |
| [CA1513](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1513) | Use ObjectDisposedException throw helper | Maintainability | No |
| [CA1514](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1514) | Avoid redundant length argument | Maintainability | No |
| [CA1515](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1515) | Consider making public types internal | Maintainability | No |
| [CA1516](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1516) | Use cross-platform intrinsics | Maintainability | No |
| [CA1700](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1700) | Do not name enum values 'Reserved' | Naming | No |
| [CA1707](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1707) | Identifiers should not contain underscores | Naming | No |
| [CA1708](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1708) | Identifiers should differ by more than case | Naming | No |
| [CA1710](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1710) | Identifiers should have correct suffix | Naming | No |
| [CA1711](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1711) | Identifiers should not have incorrect suffix | Naming | No |
| [CA1712](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1712) | Do not prefix enum values with type name | Naming | No |
| [CA1713](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1713) | Events should not have before or after prefix | Naming | No |
| [CA1714](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1714) | Flags enums should have plural names | Naming | No |
| [CA1715](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1715) | Identifiers should have correct prefix | Naming | No |
| [CA1716](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1716) | Identifiers should not match keywords | Naming | No |
| [CA1717](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1717) | Only FlagsAttribute enums should have plural names | Naming | No |
| [CA1720](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1720) | Identifiers should not contain type names | Naming | No |
| [CA1721](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1721) | Property names should not match get methods | Naming | No |
| [CA1724](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1724) | Type Names Should Not Match Namespaces | Naming | No |
| [CA1725](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1725) | Parameter names should match base declaration | Naming | No |
| [CA1727](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1727) | Use PascalCase for named placeholders | Naming | No |
| [CA1801](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1801) | Review unused parameters | Usage | No |
| [CA1802](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1802) | Use Literals Where Appropriate | Performance | No |
| [CA1805](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1805) | Do not initialize unnecessarily | Performance | No |
| [CA1806](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1806) | Do not ignore method results | Performance | No |
| [CA1810](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1810) | Initialize reference type static fields inline | Performance | No |
| [CA1812](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1812) | Avoid uninstantiated internal classes | Performance | No |
| [CA1813](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1813) | Avoid unsealed attributes | Performance | No |
| [CA1814](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1814) | Prefer jagged arrays over multidimensional | Performance | No |
| [CA1815](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1815) | Override equals and operator equals on value types | Performance | No |
| [CA1816](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1816) | Call GC.SuppressFinalize correctly | Usage | No |
| [CA1819](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1819) | Properties should not return arrays | Performance | No |
| [CA1820](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1820) | Test for empty strings using string length | Performance | No |
| [CA1821](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1821) | Remove empty finalizers | Performance | No |
| [CA1822](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1822) | Mark members as static | Performance | No |
| [CA1823](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1823) | Avoid unused private fields | Performance | No |
| [CA1824](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1824) | Mark assemblies with NeutralResourcesLanguageAttribute | Performance | No |
| [CA1825](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1825) | Avoid zero-length array allocations | Performance | No |
| [CA1826](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1826) | Use property instead of Linq Enumerable method | Performance | No |
| [CA1827](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1827) | Do not use Count/LongCount when Any can be used | Performance | No |
| [CA1828](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1828) | Do not use CountAsync/LongCountAsync when AnyAsync can be used | Performance | No |
| [CA1829](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1829) | Use Length/Count property instead of Enumerable.Count method | Performance | No |
| [CA1830](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1830) | Prefer strongly-typed Append and Insert method overloads on StringBuilder | Performance | No |
| [CA1831](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1831) | Use AsSpan instead of Range-based indexers for string when appropriate | Performance | Yes |
| [CA1832](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1832) | Use AsSpan or AsMemory instead of Range-based indexers for getting ReadOnlySpan or ReadOnlyMemory portion of an array | Performance | No |
| [CA1833](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1833) | Use AsSpan or AsMemory instead of Range-based indexers for getting Span or Memory portion of an array | Performance | No |
| [CA1834](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1834) | Use StringBuilder.Append(char) for single character strings | Performance | No |
| [CA1835](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1835) | Prefer the `Memory`-based overloads for `ReadAsync` and `WriteAsync` | Performance | No |
| [CA1836](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1836) | Prefer `IsEmpty` over `Count` when available | Performance | No |
| [CA1837](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1837) | Use `Environment.ProcessId` instead of `Process.GetCurrentProcess().Id` | Performance | No |
| [CA1838](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1838) | Avoid `StringBuilder` parameters for P/Invokes | Performance | No |
| [CA1839](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1839) | Use Environment.ProcessPath instead of Process.GetCurrentProcess().MainModule.FileName | Performance | No |
| [CA1840](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1840) | Use Environment.CurrentManagedThreadId instead of Thread.CurrentThread.ManagedThreadId | Performance | No |
| [CA1841](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1841) | Prefer Dictionary Contains methods | Performance | No |
| [CA1842](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1842) | Do not use `WhenAll` with a single task | Performance | No |
| [CA1843](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1843) | Do not use `WaitAll` with a single task | Performance | No |
| [CA1844](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1844) | Provide memory-based overrides of async methods when subclassing `Stream` | Performance | No |
| [CA1845](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1845) | Use span-based `string.Concat` | Performance | No |
| [CA1846](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1846) | Prefer `AsSpan` over `Substring` | Performance | No |
| [CA1847](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1847) | Use char literal for a single character lookup | Performance | No |
| [CA1848](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1848) | Use the LoggerMessage delegates | Performance | No |
| [CA1849](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1849) | Call async methods when in an async method | Performance | No |
| [CA1850](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1850) | Prefer static `HashData` method over `ComputeHash` | Performance | No |
| [CA1851](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1851) | Possible multiple enumerations of `IEnumerable` collection | Performance | No |
| [CA1852](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1852) | Seal internal types | Performance | No |
| [CA1853](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1853) | Unnecessary call to `Dictionary.ContainsKey(key)` | Performance | No |
| [CA1854](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1854) | Prefer the `IDictionary.TryGetValue(TKey, out TValue)` method | Performance | No |
| [CA1855](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1855) | Use Span&lt;T&gt;.Clear() instead of Span&lt;T&gt;.Fill() | Performance | No |
| [CA1856](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1856) | Incorrect usage of ConstantExpected attribute | Performance | Yes |
| [CA1857](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1857) | The parameter expects a constant for optimal performance | Performance | Yes |
| [CA1858](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1858) | Use StartsWith instead of IndexOf | Performance | No |
| [CA1859](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1859) | Use concrete types when possible for improved performance | Performance | No |
| [CA1860](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1860) | Avoid using `Enumerable.Any()` extension method | Performance | No |
| [CA1861](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1861) | Avoid constant arrays as arguments | Performance | No |
| [CA1862](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1862) | Use the `StringComparison` method overloads to perform case-insensitive string comparisons | Performance | No |
| [CA1863](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1863) | Use `CompositeFormat` | Performance | No |
| [CA1864](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1864) | Prefer the `IDictionary.TryAdd(TKey, TValue)` method | Performance | No |
| [CA1865](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1865) | Use char overload | Performance | No |
| [CA1868](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1868) | Unnecessary call to `Contains` for sets | Performance | No |
| [CA1869](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1869) | Cache and reuse `JsonSerializerOptions` instances | Performance | No |
| [CA1870](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1870) | Use a cached `SearchValues` instance | Performance | No |
| [CA1871](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1871) | Do not pass a nullable struct to `ArgumentNullException.ThrowIfNull` | Performance | No |
| [CA1872](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1872) | Prefer `Convert.ToHexString` and `Convert.ToHexStringLower` over call chains based on `BitConverter.ToString` | Performance | No |
| [CA1873](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1873) | Avoid potentially expensive logging | Performance | No |
| [CA1874](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1874) | Use `Regex.IsMatch` | Performance | No |
| [CA1875](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1875) | Use `Regex.Count` | Performance | No |
| [CA1877](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1877) | Use 'Path.Combine' or 'Path.Join' overloads | Performance | No |
| [CA2000](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2000) | Dispose objects before losing scope | Reliability | No |
| [CA2002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2002) | Do not lock on objects with weak identity | Reliability | No |
| [CA2007](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2007) | Do not directly await a Task | Reliability | No |
| [CA2008](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2008) | Do not create tasks without passing a TaskScheduler | Reliability | No |
| [CA2009](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2009) | Do not call ToImmutableCollection on an ImmutableCollection value | Reliability | No |
| [CA2011](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2011) | Do not assign property within its setter | Reliability | No |
| [CA2012](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2012) | Use ValueTasks correctly | Reliability | No |
| [CA2013](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2013) | Do not use ReferenceEquals with value types | Reliability | Yes |
| [CA2014](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2014) | Do not use stackalloc in loops. | Reliability | Yes |
| [CA2015](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2015) | Do not define finalizers for types derived from MemoryManager&lt;T&gt; | Reliability | Yes |
| [CA2016](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2016) | Forward the CancellationToken parameter to methods that take one | Reliability | No |
| [CA2017](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2017) | Parameter count mismatch | Reliability | Yes |
| [CA2018](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2018) | The `count` argument to `Buffer.BlockCopy` should specify the number of bytes to copy | Reliability | Yes |
| [CA2019](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2019) | `ThreadStatic` fields should not use inline initialization | Reliability | No |
| [CA2020](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2020) | Prevent behavioral change caused by built-in operators of IntPtr/UIntPtr | Reliability | No |
| [CA2021](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2021) | Don't call Enumerable.Cast&lt;T&gt; or Enumerable.OfType&lt;T&gt; with incompatible types | Reliability | Yes |
| [CA2022](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2022) | Avoid inexact read with Stream.Read | Reliability | Yes |
| [CA2023](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2023) | Invalid braces in message template | Reliability | Yes |
| [CA2024](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2024) | Do not use StreamReader.EndOfStream in async methods | Reliability | Yes |
| [CA2025](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2025) | Do not pass `IDisposable` instances into unawaited tasks | Reliability | No |
| [CA2026](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2026) | Prefer JsonElement.Parse over JsonDocument.Parse().RootElement | Reliability | No |
| [CA2100](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2100) | Review SQL queries for security vulnerabilities | Security | No |
| [CA2101](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2101) | Specify marshalling for P/Invoke string arguments | Globalization | No |
| [CA2109](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2109) | Review visible event handlers | Security | No |
| [CA2119](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2119) | Seal methods that satisfy private interfaces | Security | No |
| [CA2153](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2153) | Avoid handling Corrupted State Exceptions | Security | No |
| [CA2200](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2200) | Rethrow to preserve stack details | Usage | Yes |
| [CA2201](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2201) | Do not raise reserved exception types | Usage | No |
| [CA2207](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2207) | Initialize value type static fields inline | Usage | No |
| [CA2208](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2208) | Instantiate argument exceptions correctly | Usage | No |
| [CA2211](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2211) | Non-constant fields should not be visible | Usage | No |
| [CA2213](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2213) | Disposable fields should be disposed | Usage | No |
| [CA2214](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2214) | Do not call overridable methods in constructors | Usage | No |
| [CA2215](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2215) | Dispose methods should call base class dispose | Usage | No |
| [CA2216](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2216) | Disposable types should declare finalizer | Usage | No |
| [CA2217](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2217) | Do not mark enums with FlagsAttribute | Usage | No |
| [CA2218](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2218) | Override GetHashCode on overriding Equals | Usage | No |
| [CA2219](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2219) | Do not raise exceptions in exception clauses | Usage | No |
| [CA2224](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2224) | Override equals on overloading operator equals | Usage | No |
| [CA2225](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2225) | Operator overloads have named alternates | Usage | No |
| [CA2226](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2226) | Operators should have symmetrical overloads | Usage | No |
| [CA2227](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2227) | Collection properties should be read only | Usage | No |
| [CA2229](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2229) | Implement serialization constructors | Usage | No |
| [CA2231](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2231) | Overload operator equals on overriding ValueType.Equals | Usage | No |
| [CA2234](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2234) | Pass System.Uri objects instead of strings | Usage | No |
| [CA2235](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2235) | Mark all non-serializable fields | Usage | No |
| [CA2237](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2237) | Mark ISerializable types with SerializableAttribute | Usage | No |
| [CA2241](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2241) | Provide correct arguments to formatting methods | Usage | No |
| [CA2242](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2242) | Test for NaN correctly | Usage | No |
| [CA2243](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2243) | Attribute string literals should parse correctly | Usage | No |
| [CA2244](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2244) | Do not duplicate indexed element initializations | Usage | No |
| [CA2245](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2245) | Do not assign a property to itself | Usage | No |
| [CA2246](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2246) | Do not assign a symbol and its member in the same statement | Usage | No |
| [CA2247](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2247) | Argument passed to TaskCompletionSource constructor should be TaskCreationOptions enum instead of TaskContinuationOptions enum. | Usage | Yes |
| [CA2248](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2248) | Provide correct enum argument to Enum.HasFlag | Usage | No |
| [CA2249](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2249) | Consider using String.Contains instead of String.IndexOf | Usage | No |
| [CA2250](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2250) | Use `ThrowIfCancellationRequested` | Usage | No |
| [CA2251](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2251) | Use `String.Equals` over `String.Compare` | Usage | No |
| [CA2252](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2252) | Opt in to preview features | Usage | Yes |
| [CA2253](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2253) | Named placeholders should not be numeric values | Usage | No |
| [CA2254](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2254) | Template should be a static expression | Usage | No |
| [CA2255](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2255) | The `ModuleInitializer` attribute should not be used in libraries | Usage | Yes |
| [CA2256](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2256) | All members declared in parent interfaces must have an implementation in a DynamicInterfaceCastableImplementation-attributed interface | Usage | Yes |
| [CA2257](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2257) | Members defined on an interface with `DynamicInterfaceCastableImplementationAttribute` should be `static` | Usage | Yes |
| [CA2258](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2258) | Providing a `DynamicInterfaceCastableImplementation` interface in Visual Basic is unsupported | Usage | Yes |
| [CA2259](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2259) | Ensure `ThreadStatic` is only used with static fields | Usage | Yes |
| [CA2260](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2260) | Implement generic math interfaces correctly | Usage | Yes |
| [CA2261](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2261) | Do not use `ConfigureAwaitOptions.SuppressThrowing` with `Task<TResult>` | Usage | Yes |
| [CA2262](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2262) | Set `MaxResponseHeadersLength` properly | Usage | No |
| [CA2263](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2263) | Prefer generic overload when type is known | Usage | No |
| [CA2264](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2264) | Do not pass a non-nullable value to `ArgumentNullException.ThrowIfNull` | Usage | Yes |
| [CA2265](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2265) | Do not compare `Span<T>` to `null` or `default` | Usage | Yes |
| [CA2266](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2266) | File-based program entry point should start with `#!` | Usage | Yes |
| [CA2300](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2300) | Do not use insecure deserializer BinaryFormatter | Security | No |
| [CA2301](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2301) | Do not call BinaryFormatter.Deserialize without first setting BinaryFormatter.Binder | Security | No |
| [CA2302](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2302) | Ensure BinaryFormatter.Binder is set before calling BinaryFormatter.Deserialize | Security | No |
| [CA2305](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2305) | Do not use insecure deserializer LosFormatter | Security | No |
| [CA2310](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2310) | Do not use insecure deserializer NetDataContractSerializer | Security | No |
| [CA2311](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2311) | Do not deserialize without first setting NetDataContractSerializer.Binder | Security | No |
| [CA2312](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2312) | Ensure NetDataContractSerializer.Binder is set before deserializing | Security | No |
| [CA2315](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2315) | Do not use insecure deserializer ObjectStateFormatter | Security | No |
| [CA2321](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2321) | Do not deserialize with JavaScriptSerializer using a SimpleTypeResolver | Security | No |
| [CA2322](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2322) | Ensure JavaScriptSerializer is not initialized with SimpleTypeResolver before deserializing | Security | No |
| [CA2326](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2326) | Do not use TypeNameHandling values other than None | Security | No |
| [CA2327](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2327) | Do not use insecure JsonSerializerSettings | Security | No |
| [CA2328](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2328) | Ensure that JsonSerializerSettings are secure | Security | No |
| [CA2329](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2329) | Do not deserialize with JsonSerializer using an insecure configuration | Security | No |
| [CA2330](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2330) | Ensure that JsonSerializer has a secure configuration when deserializing | Security | No |
| [CA2350](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2350) | Ensure DataTable.ReadXml()'s input is trusted | Security | No |
| [CA2351](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2351) | Ensure DataSet.ReadXml()'s input is trusted | Security | No |
| [CA2352](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2352) | Unsafe DataSet or DataTable in serializable type can be vulnerable to remote code execution attacks | Security | No |
| [CA2353](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2353) | Unsafe DataSet or DataTable in serializable type | Security | No |
| [CA2354](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2354) | Unsafe DataSet or DataTable in deserialized object graph can be vulnerable to remote code execution attack | Security | No |
| [CA2355](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2355) | Unsafe DataSet or DataTable in deserialized object graph | Security | No |
| [CA2356](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2356) | Unsafe DataSet or DataTable in web deserialized object graph | Security | No |
| [CA2361](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2361) | Ensure autogenerated class containing DataSet.ReadXml() is not used with untrusted data | Security | No |
| [CA2362](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca2362) | Unsafe DataSet or DataTable in autogenerated serializable type can be vulnerable to remote code execution attacks | Security | No |
| [CA3001](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3001) | Review code for SQL injection vulnerabilities | Security | No |
| [CA3002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3002) | Review code for XSS vulnerabilities | Security | No |
| [CA3003](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3003) | Review code for file path injection vulnerabilities | Security | No |
| [CA3004](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3004) | Review code for information disclosure vulnerabilities | Security | No |
| [CA3005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3005) | Review code for LDAP injection vulnerabilities | Security | No |
| [CA3006](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3006) | Review code for process command injection vulnerabilities | Security | No |
| [CA3007](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3007) | Review code for open redirect vulnerabilities | Security | No |
| [CA3008](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3008) | Review code for XPath injection vulnerabilities | Security | No |
| [CA3009](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3009) | Review code for XML injection vulnerabilities | Security | No |
| [CA3010](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3010) | Review code for XAML injection vulnerabilities | Security | No |
| [CA3011](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3011) | Review code for DLL injection vulnerabilities | Security | No |
| [CA3012](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3012) | Review code for regex injection vulnerabilities | Security | No |
| [CA3061](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3061) | Do not add schema by URL | Security | No |
| [CA3075](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3075) | Insecure DTD Processing | Security | No |
| [CA3076](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3076) | Insecure XSLT Script Execution | Security | No |
| [CA3077](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3077) | Insecure Processing in API Design, XML Document and XML Text Reader | Security | No |
| [CA3147](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca3147) | Mark verb handlers with ValidateAntiForgeryToken | Security | No |
| [CA5350](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5350) | Do Not Use Weak Cryptographic Algorithms | Security | No |
| [CA5351](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5351) | Do Not Use Broken Cryptographic Algorithms | Security | No |
| [CA5358](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5358) | Do Not Use Unsafe Cipher Modes | Security | No |
| [CA5359](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5359) | Do not disable certificate validation | Security | No |
| [CA5360](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5360) | Do not call dangerous methods in deserialization | Security | No |
| [CA5361](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5361) | Do not disable Schannel use of strong crypto | Security | No |
| [CA5362](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5362) | Potential reference cycle in deserialized object graph | Security | No |
| [CA5363](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5363) | Do not disable request validation | Security | No |
| [CA5364](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5364) | Do not use deprecated security protocols | Security | No |
| [CA5365](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5365) | Do Not Disable HTTP Header Checking | Security | No |
| [CA5366](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5366) | Use XmlReader For DataSet Read XML | Security | No |
| [CA5367](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5367) | Do Not Serialize Types With Pointer Fields | Security | No |
| [CA5368](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5368) | Set ViewStateUserKey For Classes Derived From Page | Security | No |
| [CA5369](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5369) | Use XmlReader for Deserialize | Security | No |
| [CA5370](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5370) | Use XmlReader for validating reader | Security | No |
| [CA5371](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5371) | Use XmlReader for schema read | Security | No |
| [CA5372](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5372) | Use XmlReader for XPathDocument | Security | No |
| [CA5373](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5373) | Do not use obsolete key derivation function | Security | No |
| [CA5374](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5374) | Do Not Use XslTransform | Security | No |
| [CA5375](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5375) | Do not use account shared access signature | Security | No |
| [CA5376](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5376) | Use SharedAccessProtocol HttpsOnly | Security | No |
| [CA5377](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5377) | Use container level access policy | Security | No |
| [CA5378](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5378) | Do not disable ServicePointManagerSecurityProtocols | Security | No |
| [CA5379](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5379) | Do not use weak key derivation function algorithm | Security | No |
| [CA5380](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5380) | Do not add certificates to root store | Security | No |
| [CA5381](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5381) | Ensure certificates are not added to root store | Security | No |
| [CA5382](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5382) | Use secure cookies in ASP.NET Core | Security | No |
| [CA5383](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5383) | Ensure use secure cookies in ASP.NET Core | Security | No |
| [CA5384](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5384) | Do not use digital signature algorithm (DSA) | Security | No |
| [CA5385](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5385) | Use Rivest–Shamir–Adleman (RSA) algorithm with sufficient key size | Security | No |
| [CA5386](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5386) | Avoid hardcoding SecurityProtocolType value | Security | No |
| [CA5387](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5387) | Do not use weak key derivation function with insufficient iteration count | Security | No |
| [CA5388](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5388) | Ensure sufficient iteration count when using weak key derivation function | Security | No |
| [CA5389](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5389) | Do not add archive item's path to the target file system path | Security | No |
| [CA5390](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5390) | Do not hard-code encryption key | Security | No |
| [CA5391](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5391) | Use antiforgery tokens in ASP.NET Core MVC controllers | Security | No |
| [CA5392](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5392) | Use DefaultDllImportSearchPaths attribute for P/Invokes | Security | No |
| [CA5393](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5393) | Do not use unsafe DllImportSearchPath value | Security | No |
| [CA5394](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5394) | Do not use insecure randomness | Security | No |
| [CA5395](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5395) | Miss HttpVerb attribute for action methods | Security | No |
| [CA5396](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5396) | Set HttpOnly to true for HttpCookie | Security | No |
| [CA5397](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5397) | Do not use deprecated SslProtocols values | Security | No |
| [CA5398](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5398) | Avoid hardcoded SslProtocols values | Security | No |
| [CA5399](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5399) | Definitely disable HttpClient certificate revocation list check | Security | No |
| [CA5400](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5400) | Ensure HttpClient certificate revocation list check is not disabled | Security | No |
| [CA5401](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5401) | Do not use CreateEncryptor with non-default IV | Security | No |
| [CA5402](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5402) | Use CreateEncryptor with the default IV | Security | No |
| [CA5403](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5403) | Do not hard-code certificate | Security | No |
| [CA5404](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5404) | Do not disable token validation checks | Security | No |
| [CA5405](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca5405) | Do not always skip token validation in delegates | Security | No |
| [IL3000](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/il3000) | Avoid accessing Assembly file path when publishing as a single file | Publish (Single-file) | Yes |
| [IL3001](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/il3001) | Avoid accessing Assembly file path when publishing as a single-file | Publish (Single-file) | Yes |
| [IL3002](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/il3002) | Avoid calling members annotated with `RequiresAssemblyFilesAttribute` when publishing as a single file | Publish (Single-file) | No |
| [IL3003](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/il3003) | `RequiresAssemblyFilesAttribute` annotations must match across all interface implementations or overrides. | Publish (Single-file) | No |
| [IL3005](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/il3005) | `RequiresAssemblyFilesAttribute` cannot be placed directly on application entry point. | Publish (Single-file) | No |

