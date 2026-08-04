namespace AtG.ManagedRewrite;

public sealed record StringRewriteSpec(
    string MethodToken,
    int IlOffset,
    string Original,
    string Translation,
    string? Operation = null);

public sealed record RewriteResult(int RewrittenCount, string OutputPath);

public sealed record LdstrEntry(
    string MethodToken,
    int IlOffset,
    string TypeFullName,
    string MethodName,
    string Value);
