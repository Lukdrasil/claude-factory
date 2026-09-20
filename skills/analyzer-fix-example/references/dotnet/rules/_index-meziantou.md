# Meziantou.Analyzer: all rules
Doc URL pattern: https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/<ID>.md
| ID | Title | Default severity | Enabled by default |
|----|-------|------------------|--------------------|
| MA0001 | StringComparison is missing | Info | Yes |
| MA0002 | IEqualityComparer<string> or IComparer<string> is missing | Warning | Yes |
| MA0003 | Add parameter name to improve readability | Info | Yes |
| MA0004 | Use Task.ConfigureAwait | Warning | Yes |
| MA0005 | Use Array.Empty<T>() | Warning | Yes |
| MA0006 | Use String.Equals instead of equality operator | Warning | Yes |
| MA0007 | Add a comma after the last value | Info | Yes |
| MA0008 | Add StructLayoutAttribute | Warning | Yes |
| MA0009 | Add regex evaluation timeout | Warning | Yes |
| MA0010 | Mark attributes with AttributeUsageAttribute | Warning | Yes |
| MA0011 | IFormatProvider is missing | Warning | Yes |
| MA0012 | Do not raise reserved exception type | Warning | Yes |
| MA0013 | Types should not extend System.ApplicationException | Warning | Yes |
| MA0014 | Do not raise System.ApplicationException type | Warning | Yes |
| MA0015 | Specify the parameter name in ArgumentException | Warning | Yes |
| MA0016 | Prefer using collection abstraction instead of implementation | Warning | Yes |
| MA0017 | Abstract types should not have public or internal constructors | Warning | Yes |
| MA0018 | Do not declare static members on generic types (deprecated; use CA1000 instead) | Info | Yes |
| MA0019 | Use EventArgs.Empty | Warning | Yes |
| MA0020 | Use direct methods instead of LINQ methods | Info | Yes |
| MA0021 | Use StringComparer.GetHashCode instead of string.GetHashCode | Warning | Yes |
| MA0022 | Return Task.FromResult instead of returning null | Warning | Yes |
| MA0023 | Use RegexOptions.ExplicitCapture or named groups | Warning | Yes |
| MA0024 | Use an explicit StringComparer when possible | Warning | Yes |
| MA0025 | Implement the functionality instead of throwing NotImplementedException | Warning | Yes |
| MA0026 | Fix TODO comment | Warning | Yes |
| MA0027 | Prefer rethrowing an exception implicitly | Warning | Yes |
| MA0028 | Optimize StringBuilder usage | Info | Yes |
| MA0029 | Combine LINQ methods | Info | Yes |
| MA0030 | Remove useless OrderBy call | Warning | Yes |
| MA0031 | Optimize Enumerable.Count() usage | Info | Yes |
| MA0032 | Use an overload with a CancellationToken argument, even when no token is available in scope | Info | No |
| MA0033 | Do not tag instance fields with ThreadStaticAttribute | Warning | Yes |
| MA0035 | Do not use dangerous threading methods | Warning | Yes |
| MA0036 | Make class static | Info | Yes |
| MA0037 | Remove empty statement | Disabled | Yes |
| MA0038 | Make method static (deprecated, use CA1822 instead) | Info | Yes |
| MA0039 | Do not write your own certificate validation method | Disabled | Yes |
| MA0040 | Forward the CancellationToken parameter to methods that take one | Info | Yes |
| MA0041 | Make property static (deprecated, use CA1822 instead) | Info | Yes |
| MA0042 | Do not use blocking calls when the calling method is async | Info | Yes |
| MA0043 | Use nameof operator in ArgumentException | Info | Yes |
| MA0044 | Remove useless ToString call | Info | Yes |
| MA0045 | Do not use blocking calls, even when the calling method must become async | Info | No |
| MA0046 | Use EventHandler<T> to declare events | Warning | Yes |
| MA0047 | Declare types in namespaces | Warning | Yes |
| MA0048 | File name must match type name | Warning | Yes |
| MA0049 | Type name should not match containing namespace | Disabled | Yes |
| MA0050 | Validate arguments correctly in iterator methods | Info | Yes |
| MA0051 | Method is too long | Warning | Yes |
| MA0052 | Replace constant Enum.ToString with nameof | Info | Yes |
| MA0053 | Make class or record sealed | Info | Yes |
| MA0054 | Embed the caught exception as innerException | Warning | Yes |
| MA0055 | Do not use finalizer | Warning | Yes |
| MA0056 | Do not call overridable members in constructor | Warning | Yes |
| MA0057 | Class name should end with 'Attribute' | Info | Yes |
| MA0058 | Class name should end with 'Exception' | Info | Yes |
| MA0059 | Class name should end with 'EventArgs' | Info | Yes |
| MA0060 | The return value of the method should be used | Warning | Yes |
| MA0061 | Method overrides should not change default values | Warning | Yes |
| MA0062 | Non-flags enums should not be marked with "FlagsAttribute" | Warning | Yes |
| MA0063 | Use Where before OrderBy | Info | Yes |
| MA0064 | Avoid locking on publicly accessible instance | Warning | Yes |
| MA0065 | Default ValueType.Equals or HashCode is used for struct equality | Warning | Yes |
| MA0066 | Hash table unfriendly type is used in a hash table | Warning | Yes |
| MA0067 | Use Guid.Empty | Info | Yes |
| MA0068 | Invalid parameter name for nullable attribute | Warning | Yes |
| MA0069 | Non-constant static fields should not be visible | Warning | Yes |
| MA0070 | Obsolete attributes should include explanations | Warning | Yes |
| MA0071 | Avoid using redundant else | Info | Yes |
| MA0072 | Do not throw from a finally block | Warning | Yes |
| MA0073 | Avoid comparison with bool constant | Info | Yes |
| MA0074 | Avoid implicit culture-sensitive methods | Warning | Yes |
| MA0075 | Do not use implicit culture-sensitive ToString | Info | Yes |
| MA0076 | Do not use implicit culture-sensitive ToString in interpolated strings | Info | Yes |
| MA0077 | A class that provides Equals(T) should implement IEquatable<T> | Warning | Yes |
| MA0078 | Use 'Cast' instead of 'Select' to cast | Info | Yes |
| MA0079 | Forward the CancellationToken using .WithCancellation() | Info | Yes |
| MA0080 | Use a cancellation token using .WithCancellation() | Info | No |
| MA0081 | Method overrides should not omit params keyword | Warning | Yes |
| MA0082 | NaN should not be used in comparisons | Warning | Yes |
| MA0083 | ConstructorArgument parameters should exist in constructors | Warning | Yes |
| MA0084 | Local variables should not hide other symbols | Warning | Yes |
| MA0085 | Anonymous delegates should not be used to unsubscribe from Events | Warning | Yes |
| MA0086 | Do not throw from a finalizer | Warning | Yes |
| MA0087 | Parameters with [DefaultParameterValue] attributes should also be marked [Optional] | Warning | Yes |
| MA0088 | Use [DefaultParameterValue] instead of [DefaultValue] | Warning | Yes |
| MA0089 | Optimize string method usage | Info | Yes |
| MA0090 | Remove empty else/finally block | Info | Yes |
| MA0091 | Sender should be 'this' for instance events | Warning | Yes |
| MA0092 | Sender should be 'null' for static events | Warning | Yes |
| MA0093 | EventArgs should not be null when raising an event | Warning | Yes |
| MA0094 | A class that provides CompareTo(T) should implement IComparable<T> | Warning | Yes |
| MA0095 | A class that implements IEquatable<T> should override Equals(object) | Warning | Yes |
| MA0096 | A class that implements IComparable<T> should also implement IEquatable<T> | Warning | Yes |
| MA0097 | A class that implements IComparable<T> or IComparable should override comparison operators | Warning | Yes |
| MA0098 | Use indexer instead of LINQ methods | Info | Yes |
| MA0099 | Use Explicit enum value instead of 0 | Warning | Yes |
| MA0100 | Await task before disposing of resources | Warning | Yes |
| MA0101 | String contains an implicit end of line character | Hidden | Yes |
| MA0102 | Make member readonly | Info | Yes |
| MA0103 | Use SequenceEqual instead of equality operator | Warning | Yes |
| MA0104 | Do not create a type with a name from the BCL | Warning | No |
| MA0105 | Use the lambda parameters instead of using a closure | Info | Yes |
| MA0106 | Avoid closure by using an overload with the 'factoryArgument' parameter | Info | Yes |
| MA0107 | Do not use object.ToString | Info | No |
| MA0108 | Remove redundant argument value | Info | Yes |
| MA0109 | Consider adding an overload with a Span<T> or Memory<T> | Info | No |
| MA0110 | Use the Regex source generator | Info | Yes |
| MA0111 | Use string.Create instead of FormattableString | Info | Yes |
| MA0112 | Use 'Count > 0' instead of 'Any()' | Info | No |
| MA0113 | Use DateTime.UnixEpoch | Info | Yes |
| MA0114 | Use DateTimeOffset.UnixEpoch | Info | Yes |
| MA0115 | Unknown component parameter | Warning | Yes |
| MA0116 | Parameters with [SupplyParameterFromQuery] attributes should also be marked as [Parameter] | Warning | Yes |
| MA0117 | Parameters with [EditorRequired] attributes should also be marked as [Parameter] | Warning | Yes |
| MA0118 | [JSInvokable] methods must be public | Warning | Yes |
| MA0119 | JSRuntime must not be used in OnInitialized or OnInitializedAsync | Warning | Yes |
| MA0120 | Use InvokeVoidAsync when the returned value is not used | Info | Yes |
| MA0121 | Do not overwrite parameter value | Info | No |
| MA0122 | Parameters with [SupplyParameterFromQuery] attributes are only valid in routable components (@page) | Info | Yes |
| MA0123 | Sequence number must be a constant | Warning | Yes |
| MA0124 | Microsoft.Extensions.Logging parameter type is not valid | Warning | Yes |
| MA0125 | The list of log parameter types contains an invalid type | Warning | Yes |
| MA0126 | The list of log parameter types contains a duplicate | Warning | Yes |
| MA0127 | Use String.Equals instead of is pattern | Hidden | Yes |
| MA0128 | Use 'is' operator instead of SequenceEqual | Info | Yes |
| MA0129 | Await task in using statement | Warning | Yes |
| MA0130 | GetType() should not be used on System.Type instances | Warning | Yes |
| MA0131 | ArgumentNullException.ThrowIfNull should not be used with non-nullable types | Warning | Yes |
| MA0132 | Do not convert implicitly to DateTimeOffset | Warning | Yes |
| MA0133 | Use DateTimeOffset instead of relying on the implicit conversion | Info | Yes |
| MA0134 | Observe result of async calls | Warning | Yes |
| MA0135 | The log parameter has no configured type | Warning | No |
| MA0136 | Raw String contains an implicit end of line character | Hidden | Yes |
| MA0137 | Use 'Async' suffix when a method returns an awaitable type | Warning | No |
| MA0138 | Do not use 'Async' suffix when a method does not return an awaitable type | Warning | No |
| MA0139 | Serilog parameter type is not valid | Warning | Yes |
| MA0140 | Both if and else branch have identical code | Warning | Yes |
| MA0141 | Use 'is not null' instead of '!= null' | Info | No |
| MA0142 | Use 'is null' instead of '== null' | Info | No |
| MA0143 | Primary constructor parameters should be readonly | Warning | Yes |
| MA0144 | Use System.OperatingSystem to check the current OS | Warning | Yes |
| MA0145 | Signature for [UnsafeAccessorAttribute] method is not valid | Warning | Yes |
| MA0146 | Name must be set explicitly on local functions | Warning | Yes |
| MA0147 | Avoid async void method for delegate | Warning | Yes |
| MA0148 | Use 'is' patterns instead of '==' for constant values | Info | No |
| MA0149 | Use 'is not' patterns instead of '!=' for constant values | Info | No |
| MA0150 | Do not call ToString() when the type falls back to object.ToString() | Warning | Yes |
| MA0151 | DebuggerDisplay must contain valid members | Warning | Yes |
| MA0152 | Use Unwrap instead of using await twice | Info | Yes |
| MA0153 | Do not log symbols decorated with DataClassificationAttribute directly | Warning | Yes |
| MA0154 | Use langword in XML comment | Info | Yes |
| MA0155 | Do not use async void methods | Warning | No |
| MA0156 | Use 'Async' suffix when a method returns IAsyncEnumerable<T> | Warning | No |
| MA0157 | Do not use 'Async' suffix when a method returns IAsyncEnumerable<T> | Warning | No |
| MA0158 | Use System.Threading.Lock | Warning | Yes |
| MA0159 | Use 'Order' instead of 'OrderBy' | Info | Yes |
| MA0160 | Use ContainsKey instead of TryGetValue | Info | Yes |
| MA0161 | UseShellExecute must be explicitly set | Info | No |
| MA0162 | Use Process.Start overload with ProcessStartInfo | Info | No |
| MA0163 | UseShellExecute must be false when redirecting standard input or output | Warning | Yes |
| MA0164 | Use parentheses to make not pattern clearer | Warning | Yes |
| MA0166 | Forward the TimeProvider to methods that take one | Info | Yes |
| MA0167 | Use an overload with a TimeProvider argument | Info | No |
| MA0168 | Use readonly struct for in or ref readonly parameter | Info | No |
| MA0169 | Use Equals method instead of operator | Warning | Yes |
| MA0170 | Type cannot be used as an attribute argument | Warning | No |
| MA0171 | Use 'is null' / 'is not null' instead of Nullable<T>.HasValue | Info | No |
| MA0172 | Both sides of the logical operation are identical | Warning | No |
| MA0173 | Use LazyInitializer.EnsureInitialize | Info | Yes |
| MA0174 | Record should use explicit 'class' keyword | Info | No |
| MA0175 | Record should not use explicit 'class' keyword | Info | No |
| MA0176 | Optimize guid creation | Info | Yes |
| MA0177 | Use single-line XML comment syntax when possible | Info | No |
| MA0178 | Use TimeSpan.Zero instead of TimeSpan.FromXXX(0) | Info | Yes |
| MA0179 | Use Attribute.IsDefined instead of GetCustomAttribute(s) | Info | Yes |
| MA0180 | ILogger type parameter should match containing type | Warning | No |
| MA0181 | Do not use cast | Info | No |
| MA0182 | Avoid unused internal types | Info | Yes |
| MA0183 | The format string should use placeholders | Warning | Yes |
| MA0184 | Do not use interpolated string without parameters | Hidden | Yes |
| MA0185 | Simplify string.Create when all parameters are culture invariant | Info | Yes |
| MA0186 | Equals method should use [NotNullWhen(true)] on the parameter | Info | No |
| MA0187 | Use constructor injection instead of [Inject] attribute | Info | No |
| MA0188 | Use System.TimeProvider instead of a custom time abstraction | Info | Yes |
| MA0189 | Use InlineArray instead of fixed-size buffers | Info | Yes |
| MA0190 | Use partial property instead of partial method for GeneratedRegex | Info | Yes |
| MA0191 | Do not use the null-forgiving operator | Warning | No |
| MA0192 | Use HasFlag instead of bitwise checks | Info | Yes |
| MA0193 | Use an overload with a MidpointRounding argument | Info | Yes |
| MA0194 | Merge is expressions on the same value | Info | Yes |
| MA0195 | Do not use static fields before they are initialized | Warning | Yes |
| MA0196 | Do not use inheritdoc on non-inheriting members | Warning | Yes |
| MA0197 | Add dedicated documentation on types | Info | Yes |
| MA0198 | Specify cref for ambiguous inheritdoc on types | Warning | Yes |
| MA0199 | Do not use inheritdoc on types without inheritance source | Warning | Yes |
| MA0200 | Do not use empty property patterns with non-nullable value types | Info | Yes |
| MA0201 | Do not use zero-valued enum flags in flag checks | Warning | Yes |
| MA0202 | Conditional compilation branches have identical code | Warning | Yes |
| MA0203 | Do not use return tag for void method | Warning | Yes |
| MA0204 | Remove unnecessary partial modifier | Info | Yes |
| MA0205 | Use exclusive or operator | Info | Yes |
| MA0206 | Remove unnecessary braces in type declaration | Info | Yes |
| MA0207 | [FixedAddressValueType] fields must be static | Warning | Yes |
| MA0208 | [FixedAddressValueType] fields must be value types | Warning | Yes |
| MA0209 | Use in keyword for in parameter | Info | No |
| MA0210 | Use in keyword to call the in overload | Info | No |
| MA0211 | Use multi-line syntax for XML summary comments | Info | No |
| MA0212 | Use MemoryMarshal.GetReference instead of indexing at 0 | Warning | No |
| MA0213 | Simplify negated boolean expression | Info | No |
| MA0214 | Use 'await' instead of returning the task | Info | No |
| MA0215 | Return the task instead of awaiting it | Info | No |
| MA0216 | Remove unnecessary closed modifier | Info | Yes |
