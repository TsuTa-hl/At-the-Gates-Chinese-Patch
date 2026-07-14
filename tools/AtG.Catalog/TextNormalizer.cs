using System.Text;
using System.Text.RegularExpressions;

namespace AtG.Catalog;

public static partial class TextNormalizer
{
    public static string Normalize(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        return Whitespace().Replace(value.Normalize(NormalizationForm.FormKC).Trim(), " ");
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();
}
