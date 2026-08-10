using AtG.Testing;
using Xunit;

public sealed class RuntimeTextTests
{
    public static IEnumerable<object[]> Cases => LegacyRunnerXunitBridge.DiscoverCases(typeof(RuntimeTextTests).Assembly);

    [Theory]
    [MemberData(nameof(Cases))]
    public Task Case(string _, int metadataToken) => LegacyRunnerXunitBridge.InvokeAsync(typeof(RuntimeTextTests).Assembly, metadataToken);
}
