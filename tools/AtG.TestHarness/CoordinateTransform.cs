namespace AtG.TestHarness;

public static class CoordinateTransform
{
    public const int ReferenceWidth = 2560;
    public const int ReferenceHeight = 1440;

    public static (int X, int Y) Scale(int x, int y, int clientWidth, int clientHeight) =>
        ((int)Math.Round(x * clientWidth / (double)ReferenceWidth),
         (int)Math.Round(y * clientHeight / (double)ReferenceHeight));

    public static CropRegion InferHoverCrop(int x, int y, int clientWidth, int clientHeight)
    {
        const int width = 960;
        const int height = 640;
        var left = Math.Clamp(x - width / 2, 0, Math.Max(0, clientWidth - width));
        var top = Math.Clamp(y - height / 2, 0, Math.Max(0, clientHeight - height));
        return new CropRegion(left, top, Math.Min(width, clientWidth), Math.Min(height, clientHeight));
    }
}
