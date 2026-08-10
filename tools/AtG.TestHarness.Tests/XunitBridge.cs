using AtG.Testing;
using Xunit;

public sealed class TestHarnessTests
{
    public static IEnumerable<object[]> Cases => LegacyRunnerXunitBridge.DiscoverCases(typeof(TestHarnessTests).Assembly);

    [Theory]
    [MemberData(nameof(Cases))]
    public Task Case(string _, int metadataToken) => LegacyRunnerXunitBridge.InvokeAsync(typeof(TestHarnessTests).Assembly, metadataToken);
}
