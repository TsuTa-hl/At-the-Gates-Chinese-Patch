namespace AtG.TestHarness;

public interface IWindowDriver : IDisposable
{
    int ClientWidth { get; }
    int ClientHeight { get; }
    void Move(int referenceX, int referenceY);
    void Click(int referenceX, int referenceY);
    void KeyPress(string key);
    string ReadFingerprint(CropRegion? referenceRegion);
    void Capture(string outputPath, CropRegion? referenceRegion, bool markCursor);
}
