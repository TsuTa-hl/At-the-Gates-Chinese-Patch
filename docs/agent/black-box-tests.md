# Black-Box Test Policy

This is a routing and policy index. Scenario coordinates and executable points
live in `black-box-scenarios.json`; interface-specific acceptance criteria live
in `black-box/interfaces.md`.

## Default Verification Boundary

- `Invoke-AtGVerification.ps1` always performs the real-game main-menu smoke
  unless `-StaticOnly` is explicit.
- Main-menu smoke proves startup, patch loading, and basic process stability.
  It does not prove in-game wording, layout, hovers, save loading, or every UI
  path.
- Black-box scenario replay is opt-in. Do not run it merely because a build or
  smoke succeeded.
- Random-world creation, coordinate discovery, and repeated exploratory runs
  require the user's explicit approval.

## When a Scenario Is Authorized

1. Select only the affected Active Focus interfaces and their declared points.
2. Use the designated fixed save and approved absolute coordinates.
3. Wait at most three seconds per hover; retain text/crop evidence for a pass
   and full-window captures only for state changes or failures.
4. Record the outcome in the owning interface or scenario record before a
   retry or final report.

## Coverage States

- `Active`: selected for a user-authorized replay.
- `Completed`: has current visual evidence for its declared acceptance rule.
- `Deferred`: retained for traceability but not selected by default.
- `Discovery`: candidate routing only; not a verification claim.

## Visual Gate

On a tested surface, reject raw keys, unresolved tags, mojibake, safely
localizable English, artificial Chinese spacing, clipping, or broken recursive
hover. Generated names, IDs, versions, URLs, and documented logic-sensitive
residuals remain exceptions only when their owner record says so.
