using AtG.Testing;
using Xunit;

public sealed class PatchTests
{
    public static IEnumerable<object[]> Cases => LegacyRunnerXunitBridge.DiscoverCases(typeof(PatchTests).Assembly);

    [Theory]
    [MemberData(nameof(Cases))]
    public Task Case(string _, int metadataToken) => LegacyRunnerXunitBridge.InvokeAsync(typeof(PatchTests).Assembly, metadataToken);
}
