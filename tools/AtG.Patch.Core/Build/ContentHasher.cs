using System.Security.Cryptography;
using System.Text;

namespace AtG.Patch.Core.Build;

public static class ContentHasher
{
    public static string HashFiles(IEnumerable<string> paths, string version)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        Append(hash, version);

        foreach (var path in paths.Select(Path.GetFullPath).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("Build input was not found.", path);

            Append(hash, path.Replace('\\', '/'));
            using var stream = File.OpenRead(path);
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                hash.AppendData(buffer, 0, read);
        }

        return Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
    }

    private static void Append(IncrementalHash hash, string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        hash.AppendData(BitConverter.GetBytes(bytes.Length));
        hash.AppendData(bytes);
    }
}
