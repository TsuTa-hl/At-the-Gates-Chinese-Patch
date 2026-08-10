using AtG.Testing;
using Xunit;

public sealed class CatalogTests
{
    public static IEnumerable<object[]> Cases => LegacyRunnerXunitBridge.DiscoverCases(typeof(CatalogTests).Assembly);

    [Theory]
    [MemberData(nameof(Cases))]
    public Task Case(string _, int metadataToken) => LegacyRunnerXunitBridge.InvokeAsync(typeof(CatalogTests).Assembly, metadataToken);
}
