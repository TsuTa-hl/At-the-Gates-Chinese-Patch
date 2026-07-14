namespace AtG.TestHarness;

public enum EvidenceKind
{
    Crop,
    FullWindow,
}

public static class EvidencePolicy
{
    public static EvidenceKind Select(bool stateChanged, bool failed, CropRegion? crop) =>
        stateChanged || failed || crop is null ? EvidenceKind.FullWindow : EvidenceKind.Crop;
}
