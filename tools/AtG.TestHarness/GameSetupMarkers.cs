namespace AtG.TestHarness;

public static class GameSetupMarkers
{
    public static string ReadyMarker(GameSetupMode mode) => mode switch
    {
        GameSetupMode.NewGame => "Controller   - Giving Control to Human",
        GameSetupMode.FixedSave => "World Screen - Children Initialized",
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Main-menu setup has no world-ready marker."),
    };
}
