namespace AtG.TestHarness;

public sealed record PlannedPoint(
    string ScenarioId,
    string Interface,
    TestPoint Point,
    ScenarioAction? ClearBefore,
    IReadOnlyList<string> ExpectedNo);

public sealed record PlannedState(
    string Id,
    string Interface,
    IReadOnlyList<ScenarioAction> SetupActions,
    IReadOnlyList<PlannedPoint> Points,
    IReadOnlyList<ScenarioAction> TeardownActions);

public sealed record TestSessionPlan(
    bool LaunchGameOnce,
    bool LoadFixedSaveOnce,
    IReadOnlyList<PlannedPoint> Points,
    IReadOnlyList<string> StateTransitions,
    IReadOnlyList<PlannedState> States);

public static class SessionPlanner
{
    public static TestSessionPlan Create(
        IEnumerable<TestScenario> scenarios,
        bool includeCompleted = false)
    {
        var selected = scenarios
            .Where(scenario => includeCompleted ||
                !(scenario.SkipByDefault && scenario.Status.Equals("Completed", StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var points = new List<PlannedPoint>();
        var stateOrder = new List<string>();
        var stateScenarios = new Dictionary<string, List<TestScenario>>(StringComparer.OrdinalIgnoreCase);
        foreach (var scenario in selected)
        {
            var stateId = string.IsNullOrWhiteSpace(scenario.StateId)
                ? $"{scenario.Interface}\0{scenario.Setup}"
                : scenario.StateId;
            if (!stateScenarios.TryGetValue(stateId, out var members))
            {
                members = [];
                stateScenarios.Add(stateId, members);
                stateOrder.Add(stateId);
            }
            members.Add(scenario);
            foreach (var point in scenario.Points)
            {
                var key = $"{stateId}\0{point.Id}";
                if (seen.Add(key))
                    points.Add(new PlannedPoint(
                        scenario.Id,
                        scenario.Interface,
                        point,
                        point.SkipClear ? null : scenario.ClearBeforeEachPoint,
                        scenario.ExpectedNo));
            }
        }

        var states = stateOrder.Select(stateId =>
        {
            var members = stateScenarios[stateId];
            var statePoints = points.Where(point => members.Any(member =>
                member.Id.Equals(point.ScenarioId, StringComparison.OrdinalIgnoreCase))).ToArray();
            return new PlannedState(
                stateId,
                members[0].Interface,
                MergeActionSequences(members.Select(member => member.SetupActions)),
                statePoints,
                MergeActionSequences(members.Select(member => member.TeardownActions)));
        }).ToArray();

        var transitions = selected.Select(scenario => scenario.Setup)
            .Where(setup => !string.IsNullOrWhiteSpace(setup))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var needsSave = selected.Any(scenario => scenario.RequiresFixedSave);
        return new TestSessionPlan(true, needsSave, points, transitions, states);
    }

    private static IReadOnlyList<ScenarioAction> MergeActionSequences(
        IEnumerable<IReadOnlyList<ScenarioAction>> sequences)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var merged = new List<ScenarioAction>();
        foreach (var sequence in sequences)
        {
            var key = string.Join('\u001e', sequence.Select(ActionKey));
            if (seen.Add(key)) merged.AddRange(sequence);
        }
        return merged;
    }

    private static string ActionKey(ScenarioAction action) => string.Join('\0',
        action.Action, action.X, action.Y, action.Key, action.Bookmark, action.Marker,
        action.WaitMs, action.Crop?.X, action.Crop?.Y, action.Crop?.Width,
        action.Crop?.Height, action.RequireChange, action.RepeatCount,
        string.Join('\u001d', action.Actions.Select(ActionKey)));
}
