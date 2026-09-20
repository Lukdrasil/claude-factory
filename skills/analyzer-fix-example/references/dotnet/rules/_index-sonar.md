# SonarAnalyzer.CSharp: all rules

Doc URL pattern: https://rules.sonarsource.com/csharp/RSPEC-<number>/

| ID | Title | Type (bug/code smell/vulnerability) | On by default |
|----|-------|------|---------------|
| S100 | Methods and properties should be named in PascalCase | code smell | No |
| S101 | Types should be named in PascalCase | code smell | Yes |
| S103 | Lines should not be too long | code smell | No |
| S104 | Files should not have too many lines of code | code smell | No |
| S105 | Tabulation characters should not be used | code smell | No |
| S106 | Standard outputs should not be used directly to log anything | code smell | No |
| S107 | Methods should not have too many parameters | code smell | Yes |
| S108 | Nested blocks of code should not be left empty | code smell | Yes |
| S109 | Magic numbers should not be used | code smell | No |
| S110 | Inheritance tree of classes should not be too deep | code smell | Yes |
| S112 | General or reserved exceptions should never be thrown | code smell | Yes |
| S113 | Files should end with a newline | code smell | No |
| S121 | Control structures should use curly braces | code smell | No |
| S122 | Statements should be on separate lines | code smell | No |
| S125 | Sections of code should not be commented out | code smell | Yes |
| S126 | "if ... else if" constructs should end with "else" clauses | code smell | No |
| S127 | "for" loop stop conditions should be invariant | code smell | Yes |
| S131 | "switch/Select" statements should contain a "default/Case Else" clauses | code smell | No |
| S134 | Control flow statements "if", "switch", "for", "foreach", "while", "do"  and "try" should not be nested too deeply | code smell | No |
| S138 | Functions should not have too many lines of code | code smell | No |
| S818 | Literal suffixes should be upper case | code smell | Yes |
| S881 | Increment (++) and decrement (--) operators should not be used in a method call or mixed with other operators in an expression | code smell | No |
| S907 | "goto" statement should not be used | code smell | Yes |
| S927 | Parameter names should match base declaration and other partial definitions | code smell | Yes |
| S1006 | Method overrides should not change parameter defaults | code smell | Yes |
| S1048 | Finalizers should not throw exceptions | bug | Yes |
| S1066 | Mergeable "if" statements should be combined | code smell | Yes |
| S1067 | Expressions should not be too complex | code smell | No |
| S1075 | URIs should not be hardcoded | code smell | Yes |
| S1104 | Fields should not have public accessibility | code smell | Yes |
| S1109 | A close curly brace should be located at the beginning of a line | code smell | No |
| S1110 | Redundant pairs of parentheses should be removed | code smell | Yes |
| S1116 | Empty statements should be removed | code smell | Yes |
| S1117 | Local variables should not shadow class fields or properties | code smell | Yes |
| S1118 | Utility classes should not have public constructors | code smell | Yes |
| S1121 | Assignments should not be made from within sub-expressions | code smell | Yes |
| S1123 | "Obsolete" attributes should include explanations | code smell | Yes |
| S1125 | Boolean literals should not be redundant | code smell | Yes |
| S1128 | Unnecessary "using" should be removed | code smell | No |
| S1133 | Deprecated code should be removed | code smell | Yes |
| S1134 | Track uses of "FIXME" tags | code smell | Yes |
| S1135 | Track uses of "TODO" tags | code smell | Yes |
| S1144 | Unused private types or members should be removed | code smell | Yes |
| S1147 | Exit methods should not be called | code smell | No |
| S1151 | "switch case" clauses should not have too many lines of code | code smell | No |
| S1155 | "Any()" should be used to test for emptiness | code smell | Yes |
| S1163 | Exceptions should not be thrown in finally blocks | code smell | Yes |
| S1168 | Empty arrays and collections should be returned instead of null | code smell | Yes |
| S1172 | Unused method parameters should be removed | code smell | Yes |
| S1185 | Overriding members should do more than simply call the same member in the base class | code smell | Yes |
| S1186 | Methods should not be empty | code smell | Yes |
| S1192 | String literals should not be duplicated | code smell | Yes |
| S1199 | Nested code blocks should not be used | code smell | Yes |
| S1200 | Classes should not be coupled to too many other classes | code smell | No |
| S1206 | "Equals(Object)" and "GetHashCode()" should be overridden in pairs | bug | Yes |
| S1210 | "Equals" and the comparison operators should be overridden when implementing "IComparable" | code smell | Yes |
| S1215 | "GC.Collect" should not be called | code smell | Yes |
| S1226 | Method parameters, caught exceptions and foreach variables' initial values should not be ignored | bug | No |
| S1227 | break statements should not be used except for switch cases | code smell | No |
| S1244 | Floating point numbers should not be tested for equality | bug | Yes |
| S1264 | A "while" loop should be used instead of a "for" loop | code smell | Yes |
| S1301 | "switch" statements should have at least 3 "case" clauses | code smell | No |
| S1309 | Track uses of in-source issue suppressions | code smell | No |
| S1312 | Logger fields should be "private static readonly" | code smell | No |
| S1313 | IP addresses should not be hardcoded | code smell | Yes |
| S1449 | Culture should be specified for "string" operations | code smell | No |
| S1450 | Private fields only used as local variables in methods should become local variables | code smell | Yes |
| S1451 | Track lack of copyright and license headers | code smell | No |
| S1479 | "switch" statements with many "case" clauses should have only one statement | code smell | Yes |
| S1481 | Unused local variables should be removed | code smell | Yes |
| S1541 | Methods and properties should not be too complex | code smell | No |
| S1607 | Tests should not be ignored | code smell | Yes |
| S1643 | Strings should not be concatenated using '+' in a loop | code smell | Yes |
| S1656 | Variables should not be self-assigned | bug | Yes |
| S1659 | Multiple variables should not be declared on the same line | code smell | No |
| S1694 | An abstract class should have both abstract and concrete methods | code smell | Yes |
| S1696 | NullReferenceException should not be caught | code smell | Yes |
| S1698 | "==" should not be used when "Equals" is overridden | code smell | No |
| S1699 | Constructors should only call non-overridable methods | code smell | Yes |
| S1751 | Loops with at most one iteration should be refactored | bug | Yes |
| S1764 | Identical expressions should not be used on both sides of operators | bug | Yes |
| S1821 | "switch" statements should not be nested | code smell | No |
| S1848 | Objects should not be created to be dropped immediately without being used | bug | Yes |
| S1854 | Unused assignments should be removed | code smell | Yes |
| S1858 | "ToString()" calls should not be redundant | code smell | No |
| S1862 | Related "if/else if" statements should not have the same condition | bug | Yes |
| S1871 | Two branches in a conditional structure should not have exactly the same implementation | code smell | Yes |
| S1905 | Redundant casts should not be used | code smell | Yes |
| S1939 | Inheritance list should not be redundant | code smell | Yes |
| S1940 | Boolean checks should not be inverted | code smell | Yes |
| S1944 | Invalid casts should be avoided | code smell | Yes |
| S1994 | "for" loop increment clauses should modify the loops' counters | code smell | Yes |
| S2053 | Password hashing functions should use an unpredictable salt | vulnerability | Yes |
| S2068 | Credentials should not be hard-coded | vulnerability | Yes |
| S2077 | SQL queries should not be dynamically formatted | vulnerability | Yes |
| S2092 | Cookies should have the "secure" flag | vulnerability | Yes |
| S2094 | Classes should not be empty | code smell | Yes |
| S2114 | Collections should not be passed as arguments to their own methods | bug | Yes |
| S2115 | A secure password should be used when connecting to a database | vulnerability | Yes |
| S2123 | Values should not be uselessly incremented | bug | Yes |
| S2139 | Exceptions should be either logged or rethrown but not both | code smell | Yes |
| S2148 | Underscores should be used to make large numbers readable | code smell | No |
| S2156 | "sealed" classes should not have "protected" members | code smell | No |
| S2166 | Classes named like "Exception" should extend "Exception" or a subclass | code smell | Yes |
| S2178 | Short-circuit logic should be used in boolean contexts | code smell | Yes |
| S2183 | Integral numbers should not be shifted by zero or more than their number of bits-1 | bug | Yes |
| S2184 | Results of integer division should not be assigned to floating point variables | bug | Yes |
| S2187 | Test classes should contain at least one test case | code smell | Yes |
| S2190 | Loops and recursions should not be infinite | bug | Yes |
| S2197 | Modulus results should not be checked for direct equality | code smell | No |
| S2198 | Unnecessary mathematical comparisons should not be made | code smell | Yes |
| S2201 | Methods without side effects should not have their return values ignored | bug | Yes |
| S2219 | Runtime type checking should be simplified | code smell | Yes |
| S2221 | "Exception" should not be caught | code smell | No |
| S2222 | Locks should be released on all paths | bug | Yes |
| S2223 | Non-constant static fields should not be visible | code smell | Yes |
| S2225 | "ToString()" method should not return null | bug | Yes |
| S2234 | Arguments should be passed in the same order as the method parameters | code smell | Yes |
| S2245 | Pseudorandom number generators (PRNGs) should not be used in security contexts | vulnerability | Yes |
| S2251 | A "for" loop update clause should move the counter in the right direction | bug | Yes |
| S2252 | For-loop conditions should be true at least once | bug | Yes |
| S2257 | Custom cryptographic algorithms should not be used | vulnerability | Yes |
| S2259 | Null pointers should not be dereferenced | bug | Yes |
| S2275 | Composite format strings should not lead to unexpected behavior at runtime | bug | Yes |
| S2290 | Field-like events should not be virtual | code smell | Yes |
| S2291 | Overflow checking should not be disabled for "Enumerable.Sum" | code smell | Yes |
| S2292 | Trivial properties should be auto-implemented | code smell | Yes |
| S2302 | "nameof" should be used | code smell | No |
| S2306 | "async" and "await" should not be used as identifiers | code smell | Yes |
| S2325 | Methods and properties that don't access instance data should be static | code smell | Yes |
| S2326 | Unused type parameters should be removed | code smell | Yes |
| S2327 | "try" statements with identical "catch" and/or "finally" blocks should be merged | code smell | No |
| S2328 | "GetHashCode" should not reference mutable fields | bug | Yes |
| S2330 | Array covariance should not be used | code smell | No |
| S2333 | Redundant modifiers should not be used | code smell | No |
| S2339 | Public constant members should not be used | code smell | No |
| S2342 | Enumeration types should comply with a naming convention | code smell | Yes |
| S2344 | Enumeration type names should not have "Flags" or "Enum" suffixes | code smell | Yes |
| S2345 | Flags enumerations should explicitly initialize all their members | bug | Yes |
| S2346 | Flags enumerations zero-value members should be named "None" | code smell | Yes |
| S2357 | Fields should be private | code smell | No |
| S2360 | Optional parameters should not be used | code smell | No |
| S2365 | Properties should not make collection or array copies | code smell | Yes |
| S2368 | Public methods should not have multidimensional array parameters | code smell | Yes |
| S2372 | Exceptions should not be thrown from property getters | code smell | Yes |
| S2376 | Write-only properties should not be used | code smell | Yes |
| S2386 | Mutable fields should not be "public static" | code smell | Yes |
| S2387 | Child class fields should not shadow parent class fields | code smell | No |
| S2436 | Types and methods should not have too many generic parameters | code smell | Yes |
| S2437 | Unnecessary bit operations should not be performed | code smell | Yes |
| S2445 | Blocks should be synchronized on read-only fields | bug | Yes |
| S2479 | Whitespace and control characters in string literals should be explicit | code smell | Yes |
| S2486 | Generic exceptions should not be ignored | code smell | Yes |
| S2551 | Shared resources should not be used for locking | bug | Yes |
| S2583 | Conditionally executed code should be reachable | bug | Yes |
| S2589 | Boolean expressions should not be gratuitous | code smell | Yes |
| S2612 | File permissions should not be set to world-accessible values | vulnerability | Yes |
| S2629 | Logging templates should be constant | code smell | Yes |
| S2674 | The length returned from a stream read should be checked | bug | Yes |
| S2681 | Multiline blocks should be enclosed in curly braces | code smell | Yes |
| S2688 | "NaN" should not be used in comparisons | bug | Yes |
| S2692 | "IndexOf" checks should not be for positive numbers | code smell | Yes |
| S2696 | Instance members should not write to "static" fields | code smell | Yes |
| S2699 | Tests should include assertions | code smell | Yes |
| S2701 | Literal boolean values should not be used in assertions | code smell | Yes |
| S2737 | "catch" clauses should do more than rethrow | code smell | Yes |
| S2743 | Static fields should not be used in generic types | code smell | Yes |
| S2755 | XML parsers should not be vulnerable to XXE attacks | vulnerability | Yes |
| S2757 | Non-existent operators like "=+" should not be used | bug | Yes |
| S2760 | Sequential tests should not check the same condition | code smell | No |
| S2761 | Doubled prefix operators "!!" and "~~" should not be used | bug | Yes |
| S2857 | SQL keywords should be delimited by whitespace | bug | Yes |
| S2925 | "Thread.Sleep" should not be used in tests | code smell | Yes |
| S2930 | "IDisposables" should be disposed | bug | Yes |
| S2931 | Classes with "IDisposable" members should implement "IDisposable" | bug | No |
| S2933 | Fields that are only assigned in the constructor should be "readonly" | code smell | Yes |
| S2934 | Property assignments should not be made for "readonly" fields not constrained to reference types | bug | Yes |
| S2952 | Classes should "Dispose" of members from the classes' own "Dispose" methods | bug | No |
| S2953 | Methods named "Dispose" should implement "IDisposable.Dispose" | code smell | Yes |
| S2955 | Generic parameters not constrained to reference types should not be compared to "null" | bug | Yes |
| S2970 | Assertions should be complete | code smell | Yes |
| S2971 | LINQ expressions should be simplified | code smell | Yes |
| S2995 | "Object.ReferenceEquals" should not be used for value types | bug | Yes |
| S2996 | "ThreadStatic" fields should not be initialized | bug | Yes |
| S2997 | "IDisposables" created in a "using" statement should not be returned | bug | Yes |
| S3005 | "ThreadStatic" should not be used on non-static fields | bug | Yes |
| S3010 | Static fields should not be updated in constructors | code smell | Yes |
| S3011 | Reflection should not be used to increase accessibility of classes, methods, or fields | code smell | Yes |
| S3052 | Members should not be initialized to default values | code smell | No |
| S3059 | Types should not have members with visibility set higher than the type's visibility | code smell | No |
| S3060 | "is" should not be used with "this" | code smell | Yes |
| S3063 | "StringBuilder" data should be used | code smell | Yes |
| S3168 | "async" methods should not return "void" | bug | Yes |
| S3169 | Multiple "OrderBy" calls should not be used | code smell | Yes |
| S3172 | Delegates should not be subtracted | bug | Yes |
| S3215 | "interface" instances should not be cast to concrete types | code smell | No |
| S3216 | "ConfigureAwait(false)" should be used | code smell | No |
| S3217 | "Explicit" conversions of "foreach" loops should not be used | code smell | Yes |
| S3218 | Inner class members should not shadow outer class "static" or type members | code smell | Yes |
| S3220 | Method calls should not resolve ambiguously to overloads with "params" | code smell | Yes |
| S3234 | "GC.SuppressFinalize" should not be invoked for types without destructors | code smell | No |
| S3235 | Redundant parentheses should not be used | code smell | No |
| S3236 | Caller information arguments should not be provided explicitly | code smell | Yes |
| S3237 | "value" contextual keyword should be used | code smell | Yes |
| S3240 | The simplest possible condition syntax should be used | code smell | No |
| S3241 | Methods should not return values that are never used | code smell | Yes |
| S3242 | Method parameters should be declared with base types | code smell | No |
| S3244 | Anonymous delegates should not be used to unsubscribe from Events | bug | Yes |
| S3246 | Generic type parameters should be co/contravariant when possible | code smell | Yes |
| S3247 | Duplicate casts should not be made | code smell | Yes |
| S3249 | Classes directly extending "object" should not call "base" in "GetHashCode" or "Equals" | bug | Yes |
| S3251 | Implementations should be provided for "partial" methods | code smell | Yes |
| S3253 | Constructor and destructor declarations should not be redundant | code smell | No |
| S3254 | Default parameter values should not be passed as arguments | code smell | No |
| S3256 | "string.IsNullOrEmpty" should be used | code smell | No |
| S3257 | Declarations and initializations should be as concise as possible | code smell | No |
| S3260 | Non-derived "private" classes and records should be "sealed" | code smell | Yes |
| S3261 | Namespaces should not be empty | code smell | Yes |
| S3262 | "params" should be used on overrides | code smell | Yes |
| S3263 | Static fields should appear in the order they must be initialized  | bug | Yes |
| S3264 | Events should be invoked | code smell | Yes |
| S3265 | Non-flags enums should not be used in bitwise operations | code smell | Yes |
| S3267 | Loops should be simplified with "LINQ" expressions | code smell | Yes |
| S3329 | Cipher Block Chaining IVs should be unpredictable | vulnerability | Yes |
| S3330 | Cookies should have the "HttpOnly" flag | vulnerability | Yes |
| S3343 | Caller information parameters should come at the end of the parameter list | bug | Yes |
| S3346 | Expressions used in "Debug.Assert" should not produce side effects | bug | Yes |
| S3353 | Unchanged variables should be marked as "const" | code smell | No |
| S3358 | Ternary operators should not be nested | code smell | Yes |
| S3363 | Date and time should not be used as a type for primary keys | bug | Yes |
| S3366 | "this" should not be exposed from constructors | code smell | No |
| S3376 | Attribute, EventArgs, and Exception type names should end with the type being extended | code smell | Yes |
| S3397 | "base.Equals" should not be used to check for reference equality in "Equals" if "base" is not "object" | bug | Yes |
| S3398 | "private" methods called only by inner classes should be moved to those classes | code smell | Yes |
| S3400 | Methods should not return constants | code smell | Yes |
| S3415 | Assertion arguments should be passed in the correct order | code smell | Yes |
| S3416 | Loggers should be named for their enclosing types | code smell | No |
| S3427 | Method overloads with default parameter values should not overlap | code smell | Yes |
| S3431 | "[ExpectedException]" should not be used | code smell | Yes |
| S3433 | Test method signatures should be correct | code smell | Yes |
| S3440 | Variables should not be checked against the values they're about to be assigned | code smell | Yes |
| S3441 | Redundant property names should be omitted in anonymous classes | code smell | No |
| S3442 | "abstract" classes should not have "public" constructors | code smell | Yes |
| S3443 | Type should not be examined on "System.Type" instances | code smell | Yes |
| S3444 | Interfaces should not simply inherit from base interfaces with colliding members | code smell | Yes |
| S3445 | Exceptions should not be explicitly rethrown | code smell | Yes |
| S3447 | "[Optional]" should not be used on "ref" or "out" parameters | code smell | Yes |
| S3449 | Right operands of shift operators should be integers | bug | Yes |
| S3450 | Parameters with "[DefaultParameterValue]" attributes should also be marked "[Optional]" | code smell | Yes |
| S3451 | "[DefaultValue]" should not be used when "[DefaultParameterValue]" is meant | code smell | Yes |
| S3453 | Classes should not have only "private" constructors | bug | Yes |
| S3456 | "string.ToCharArray()" and "ReadOnlySpan<T>.ToArray()" should not be called redundantly | bug | Yes |
| S3457 | Composite format strings should be used correctly | code smell | Yes |
| S3458 | Empty "case" clauses that fall through to the "default" should be omitted | code smell | Yes |
| S3459 | Unassigned members should be removed | code smell | Yes |
| S3464 | Type inheritance should not be recursive | bug | Yes |
| S3466 | Optional parameters should be passed to "base" calls | bug | Yes |
| S3532 | Empty "default" clauses should be removed | code smell | No |
| S3597 | "ServiceContract" and "OperationContract" attributes should be used together | code smell | Yes |
| S3598 | One-way "OperationContract" methods should have "void" return type | bug | Yes |
| S3600 | "params" should not be introduced on overrides | code smell | Yes |
| S3603 | Methods with "Pure" attribute should return a value  | bug | Yes |
| S3604 | Member initializer values should not be redundant | code smell | Yes |
| S3610 | Nullable type comparison should not be redundant | bug | Yes |
| S3626 | Jump statements should not be redundant | code smell | Yes |
| S3655 | Empty nullable value should not be accessed | bug | Yes |
| S3717 | Track use of "NotImplementedException" | code smell | No |
| S3776 | Cognitive Complexity of methods should not be too high | code smell | Yes |
| S3869 | "SafeHandle.DangerousGetHandle" should not be called | bug | Yes |
| S3871 | Exception types should be "public" | code smell | Yes |
| S3872 | Parameter names should not duplicate the names of their methods | code smell | No |
| S3874 | "out" and "ref" parameters should not be used | code smell | No |
| S3875 | "operator==" should not be overloaded on reference types | code smell | Yes |
| S3876 | Strings or integral types should be used for indexers | code smell | No |
| S3877 | Exceptions should not be thrown from unexpected methods | code smell | Yes |
| S3878 | Arrays should not be created for params parameters | code smell | Yes |
| S3880 | Finalizers should not be empty | code smell | No |
| S3881 | "IDisposable" should be implemented correctly | code smell | Yes |
| S3884 | "CoSetProxyBlanket" and "CoInitializeSecurity" should not be used | vulnerability | No |
| S3885 | "Assembly.Load" should be used | code smell | Yes |
| S3887 | Mutable, non-private fields should not be "readonly" | bug | Yes |
| S3889 | "Thread.Resume" and "Thread.Suspend" should not be used | bug | Yes |
| S3897 | Classes that provide "Equals(<T>)" should implement "IEquatable<T>" | code smell | Yes |
| S3898 | Value types should implement "IEquatable<T>" | code smell | No |
| S3900 | Arguments of public methods should be validated against null | code smell | No |
| S3902 | "Assembly.GetExecutingAssembly" should not be called | code smell | No |
| S3903 | Types should be defined in named namespaces | bug | Yes |
| S3904 | Assemblies should have version information | code smell | Yes |
| S3906 | Event Handlers should have the correct signature | code smell | No |
| S3908 | Generic event handlers should be used | code smell | No |
| S3909 | Collections should implement the generic interface | code smell | No |
| S3923 | All branches in a conditional structure should not have exactly the same implementation | bug | Yes |
| S3925 | "ISerializable" should be implemented correctly | code smell | Yes |
| S3926 | Deserialization methods should be provided for "OptionalField" members | bug | Yes |
| S3927 | Serialization event handlers should be implemented correctly | bug | Yes |
| S3928 | Parameter names used into ArgumentException constructors should match an existing one  | code smell | Yes |
| S3937 | Number patterns should be regular | code smell | No |
| S3949 | Calculations should not overflow | bug | Yes |
| S3956 | "Generic.List" instances should not be part of public APIs | code smell | No |
| S3962 | "static readonly" constants should be "const" instead | code smell | No |
| S3963 | "static" fields should be initialized inline | code smell | Yes |
| S3966 | Objects should not be disposed more than once | code smell | Yes |
| S3967 | Multidimensional arrays should not be used | code smell | No |
| S3971 | "GC.SuppressFinalize" should not be called | code smell | Yes |
| S3972 | Conditionals should start on new lines | code smell | Yes |
| S3973 | A conditionally executed single line should be denoted by indentation | code smell | Yes |
| S3981 | Collection sizes and array length comparisons should make sense | bug | Yes |
| S3984 | Exceptions should not be created without being thrown | bug | Yes |
| S3990 | Assemblies should be marked as CLS compliant | code smell | No |
| S3992 | Assemblies should explicitly specify COM visibility | code smell | No |
| S3993 | Custom attributes should be marked with "System.AttributeUsageAttribute" | code smell | Yes |
| S3994 | URI Parameters should not be strings | code smell | No |
| S3995 | URI return values should not be strings | code smell | No |
| S3996 | URI properties should not be strings | code smell | No |
| S3997 | String URI overloads should call "System.Uri" overloads | code smell | No |
| S3998 | Threads should not lock on objects with weak identity | code smell | Yes |
| S4000 | Pointers to unmanaged memory should not be visible | code smell | No |
| S4002 | Disposable types should declare finalizers | code smell | No |
| S4004 | Collection properties should be readonly | code smell | No |
| S4005 | "System.Uri" arguments should be used instead of strings | code smell | No |
| S4015 | Inherited member visibility should not be decreased | code smell | Yes |
| S4016 | Enumeration members should not be named "Reserved" | code smell | No |
| S4017 | Method signatures should not contain nested generic types | code smell | No |
| S4018 | All type parameters should be used in the parameter list to enable type inference | code smell | No |
| S4019 | Base class methods should not be hidden | code smell | Yes |
| S4022 | Enumerations should have "Int32" storage | code smell | No |
| S4023 | Interfaces should not be empty | code smell | No |
| S4025 | Child class fields should not differ from parent class fields only by capitalization | code smell | No |
| S4026 | Assemblies should be marked with "NeutralResourcesLanguageAttribute" | code smell | No |
| S4027 | Exceptions should provide standard constructors | code smell | No |
| S4035 | Classes implementing "IEquatable<T>" should be sealed | code smell | Yes |
| S4036 | OS commands should not rely on PATH resolution | vulnerability | Yes |
| S4039 | Interface methods should be callable by derived types | code smell | No |
| S4040 | Strings should be normalized to uppercase | code smell | No |
| S4041 | Type names should not match namespaces | code smell | No |
| S4047 | Generics should be used when appropriate | code smell | No |
| S4049 | Properties should be preferred | code smell | No |
| S4050 | Operators should be overloaded consistently | code smell | Yes |
| S4052 | Types should not extend outdated base types | code smell | Yes |
| S4055 | Literals should not be passed as localized parameters | code smell | No |
| S4056 | Overloads with a "CultureInfo" or an "IFormatProvider" parameter should be used | code smell | No |
| S4057 | Locales should be set for data types | code smell | No |
| S4058 | Overloads with a "StringComparison" parameter should be used | code smell | No |
| S4059 | Property names should not match get methods | code smell | No |
| S4060 | Non-abstract attributes should be sealed | code smell | No |
| S4061 | "params" should be used instead of "varargs" | code smell | Yes |
| S4069 | Operator overloads should have named alternatives | code smell | No |
| S4070 | Non-flags enums should not be marked with "FlagsAttribute" | code smell | Yes |
| S4136 | Method overloads should be grouped together | code smell | Yes |
| S4143 | Collection elements should not be replaced unconditionally | bug | Yes |
| S4144 | Methods should not have identical implementations | code smell | Yes |
| S4158 | Empty collections should not be accessed or iterated | bug | Yes |
| S4159 | Classes should implement their "ExportAttribute" interfaces | bug | Yes |
| S4200 | Native methods should be wrapped | code smell | Yes |
| S4201 | Null checks should not be combined with "is" operator checks | code smell | Yes |
| S4210 | Windows Forms entry points should be marked with STAThread | bug | Yes |
| S4211 | Members should not have conflicting transparency annotations | vulnerability | Yes |
| S4212 | Serialization constructors should be secured | vulnerability | No |
| S4214 | "P/Invoke" methods should not be visible | code smell | No |
| S4220 | Events should have proper arguments | code smell | Yes |
| S4225 | Extension methods should not extend "object" | code smell | No |
| S4226 | Extensions should be in separate namespaces | code smell | No |
| S4260 | "ConstructorArgument" parameters should exist in constructors | bug | Yes |
| S4261 | Methods should be named according to their synchronicities | code smell | No |
| S4275 | Getters and setters should access the expected fields | bug | Yes |
| S4277 | "Shared" parts should not be created with "new" | bug | Yes |
| S4347 | Secure random number generators should not output predictable values | vulnerability | Yes |
| S4423 | Weak SSL/TLS protocols should not be used | vulnerability | Yes |
| S4426 | Cryptographic keys should be robust | vulnerability | Yes |
| S4428 | "PartCreationPolicyAttribute" should be used with "ExportAttribute" | bug | Yes |
| S4433 | LDAP connections should be authenticated | vulnerability | Yes |
| S4456 | Parameter validation in yielding methods should be wrapped | code smell | Yes |
| S4457 | Parameter validation in "async"/"await" methods should be wrapped | code smell | No |
| S4462 | Calls to "async" methods should not be blocking | code smell | No |
| S4487 | Unread "private" fields should be removed | code smell | Yes |
| S4502 | CSRF protections should not be disabled | vulnerability | Yes |
| S4507 | Debugging features should not be enabled in production | vulnerability | Yes |
| S4524 | "default" clauses should be first or last | code smell | Yes |
| S4545 | "DebuggerDisplayAttribute" strings should reference existing members | code smell | Yes |
| S4581 | "new Guid()" should not be used | code smell | Yes |
| S4583 | Calls to delegate's method "BeginInvoke" should be paired with calls to "EndInvoke" | bug | Yes |
| S4586 | Non-async "Task/Task<T>" methods should not return null | bug | Yes |
| S4635 | Start index should be used instead of calling Substring | code smell | Yes |
| S4663 | Comments should not be empty | code smell | Yes |
| S4790 | Weak hashing algorithms should not be used | vulnerability | Yes |
| S4830 | Server certificates should be verified during SSL/TLS connections | vulnerability | Yes |
| S5034 | "ValueTask" should be consumed correctly | code smell | Yes |
| S5042 | Expanding archive files should not be done without controlling resource consumption | code smell | No |
| S5122 | Cross-Origin Resource Sharing (CORS) policy should be restricted to trusted origins | vulnerability | Yes |
| S5332 | Clear-text protocols should not be used | vulnerability | Yes |
| S5344 | Passwords should not be stored in plaintext or with a fast hashing algorithm | vulnerability | Yes |
| S5443 | Temporary files should not be created in publicly writable directories | vulnerability | Yes |
| S5445 | Insecure temporary file creation methods should not be used | vulnerability | Yes |
| S5542 | Encryption algorithms should be used with secure mode and padding scheme | vulnerability | Yes |
| S5547 | Cipher algorithms should be robust | vulnerability | Yes |
| S5659 | JWT should be signed and verified with strong cipher algorithms | vulnerability | Yes |
| S5693 | HTTP request content length should be limited | vulnerability | Yes |
| S5753 | ASP.NET Request Validation should not be disabled | vulnerability | Yes |
| S5766 | Serializable objects should validate data during deserialization | vulnerability | Yes |
| S5773 | Types allowed to be deserialized should be restricted | vulnerability | Yes |
| S5856 | Regular expressions should be syntactically valid | bug | Yes |
| S6354 | Use a testable date/time provider | code smell | No |
| S6377 | XML signatures should be validated securely | vulnerability | Yes |
| S6418 | Secrets should not be hard-coded | vulnerability | Yes |
| S6419 | Azure Functions should be stateless | code smell | Yes |
| S6420 | Client instances should not be recreated on each Azure Function invocation | code smell | Yes |
| S6421 | Azure Functions should use Structured Error Handling | code smell | No |
| S6422 | Calls to "async" methods should not be blocking in Azure Functions | code smell | Yes |
| S6423 | Azure Functions should log all failures | code smell | No |
| S6424 | Interfaces for durable entities should satisfy the restrictions | code smell | Yes |
| S6444 | Regular expressions should be executed with a timeout | vulnerability | Yes |
| S6507 | Blocks should not be synchronized on local variables | bug | No |
| S6513 | "ExcludeFromCodeCoverage" attributes should include a justification | code smell | No |
| S6561 | Avoid using "DateTime.Now" for benchmarking or timing operations | code smell | Yes |
| S6562 | Always set the "DateTimeKind" when creating new "DateTime" instances | code smell | Yes |
| S6563 | Use UTC when recording DateTime instants | code smell | No |
| S6566 | Use "DateTimeOffset" instead of "DateTime" | code smell | No |
| S6575 | Use "TimeZoneInfo.FindSystemTimeZoneById" without converting the timezones with "TimezoneConverter" | code smell | Yes |
| S6580 | Use a format provider when parsing date and time | code smell | Yes |
| S6585 | Don't hardcode the format when turning dates and times to strings | code smell | No |
| S6588 | Use the "UnixEpoch" field instead of creating "DateTime" instances that point to the beginning of the Unix epoch | code smell | Yes |
| S6602 | "Find" method should be used instead of the "FirstOrDefault" extension | code smell | No |
| S6603 | The collection-specific "TrueForAll" method should be used instead of the "All" extension | code smell | No |
| S6605 | Collection-specific "Exists" method should be used instead of the "Any" extension | code smell | No |
| S6607 | The collection should be filtered before sorting by using "Where" before "OrderBy" | code smell | Yes |
| S6608 | Prefer indexing instead of "Enumerable" methods on types implementing "IList" | code smell | Yes |
| S6609 | "Min/Max" properties of "Set" types should be used instead of the "Enumerable" extension methods | code smell | Yes |
| S6610 | "StartsWith" and "EndsWith" overloads that take a "char" should be used instead of the ones that take a "string" | code smell | Yes |
| S6612 | The lambda parameter should be used instead of capturing arguments in "ConcurrentDictionary" methods | code smell | Yes |
| S6613 | "First" and "Last" properties of "LinkedList" should be used instead of the "First()" and "Last()" extension methods | code smell | Yes |
| S6617 | "Contains" should be used instead of "Any" for simple equality checks | code smell | Yes |
| S6618 | "string.Create" should be used instead of "FormattableString" | code smell | Yes |
| S6640 | Unsafe code blocks should not be used | vulnerability | Yes |
| S6664 | The code block contains too many logging calls | code smell | Yes |
| S6667 | Logging in a catch clause should pass the caught exception as a parameter. | code smell | Yes |
| S6668 | Logging arguments should be passed to the correct parameter | code smell | Yes |
| S6669 | Logger field or property name should comply with a naming convention | code smell | Yes |
| S6670 | "Trace.Write" and "Trace.WriteLine" should not be used | code smell | Yes |
| S6672 | Generic logger injection should match enclosing type | code smell | Yes |
| S6673 | Log message template placeholders should be in the right order | code smell | Yes |
| S6674 | Log message template should be syntactically correct | bug | Yes |
| S6675 | "Trace.WriteLineIf" should not be used with "TraceSwitch" levels | code smell | Yes |
| S6677 | Message template placeholders should be unique | bug | Yes |
| S6678 | Use PascalCase for named placeholders | code smell | Yes |
| S6781 | JWT secret keys should not be disclosed | vulnerability | Yes |
| S6797 | Blazor query parameter type should be supported | bug | Yes |
| S6798 | [JSInvokable] attribute should only be used on public methods | bug | Yes |
| S6800 | Component parameter type should match the route parameter type constraint | bug | Yes |
| S6802 | Using lambda expressions in loops should be avoided in Blazor markup section | code smell | No |
| S6803 | Parameters with SupplyParameterFromQuery attribute should be used only in routable components | code smell | No |
| S6930 | Backslash should be avoided in route templates | bug | Yes |
| S6931 | ASP.NET controller actions should not have a route template starting with "/" | code smell | Yes |
| S6932 | Use model binding instead of reading raw request data | code smell | Yes |
| S6934 | A Route attribute should be added to the controller when a route template is specified at the action level | code smell | Yes |
| S6960 | Controllers should not have mixed responsibilities | code smell | Yes |
| S6961 | API Controllers should derive from ControllerBase instead of Controller | code smell | Yes |
| S6962 | You should pool HTTP connections with HttpClientFactory | code smell | Yes |
| S6964 | Value type property used as input in a controller action should be nullable, required or annotated with the JsonRequiredAttribute to avoid under-posting. | code smell | Yes |
| S6965 | REST API actions should be annotated with an HTTP verb attribute | code smell | Yes |
| S6966 | Awaitable method should be used | code smell | Yes |
| S6967 | ModelState.IsValid should be called in controller actions | code smell | Yes |
| S6968 | Actions that return a value should be annotated with ProducesResponseTypeAttribute containing the return type | code smell | Yes |
| S7039 | Content Security Policies should be restrictive | vulnerability | Yes |
| S7130 | First/Single should be used instead of FirstOrDefault/SingleOrDefault on collections that are known to be non-empty | code smell | Yes |
| S7131 | A write lock should not be released when a read lock has been acquired and vice versa | bug | Yes |
| S7133 | Locks should be released within the same method | bug | Yes |
| S8367 | Identifiers should not conflict with the C# 14 "field" contextual keyword | code smell | Yes |
| S8368 | Identifiers should not conflict with the C# 14 "extension" contextual keyword | code smell | Yes |
| S8380 | Return types named "partial" should be escaped with "@" | code smell | Yes |
| S8381 | "scoped" should be escaped when used as an identifier or type name in parenthesized lambda parameter lists | code smell | Yes |
| S8717 | Multiple "[Key]" attributes should not be used to define a composite key | bug | Yes |
| S8718 | Client-evaluated default values should use database functions | bug | Yes |
| S8733 | Potential Cartesian Explosion | bug | Yes |
| S8747 | Migrations should not narrow column types without converting existing data | bug | Yes |
| S8949 | The overload accepting a 'CancellationToken' should be used | bug | Yes |
| S8969 | Null-forgiving operators should not be redundant | code smell | Yes |
| S8970 | Null-forgiving operators should not be used when nullable warnings are disabled | code smell | Yes |
| S9022 | Redundant "Include" calls should be removed | code smell | Yes |
| S9118 | Default values should be compatible with their entity property type | bug | Yes |
| S9129 | "Include" and "ThenInclude" chains of reference navigations should be merged into a single "Include" call | code smell | Yes |
