# Workflow: Test and Loop

## Purpose

Use this workflow to run black-box tests, inspect results, and automatically
return to assessment/fix work when tests fail.

## Read First

- `docs/agent/operations.md`
- `docs/agent/black-box-tests.md`
- `docs/agent/workflows/assess-and-fix.md`
- `docs/agent/workflows/package-and-install.md`
- `docs/agent/text-sources.md` if failures include raw keys, English, mojibake,
  or unresolved tags.
- `docs/agent/translation-style.md` if failures include safely localizable
  English text or translation quality/style issues.
- `docs/agent/crash-risks.md` if failures include crashes, missing assets,
  fonts/icons, Common concepts, faction names, dates, or notification prefixes.

## Inputs

- Ready-build handoff from `package-and-install.md` for the latest patch.
- Active Focus Tests from `black-box-tests.md`.
- User-requested scenario, screenshot, or failure report.

## Steps

1. Confirm there is a ready-build handoff from `package-and-install.md` for the
   current patch. If it is missing, stale, or failed, run that workflow first.
2. Select Active Focus Tests from `black-box-tests.md`.
   Prefer machine-readable incremental scenarios in
   `docs/agent/black-box-scenarios.json`. Full-regression scenarios are opt-in;
   do not run them by default unless the touched source can affect many
   interfaces, the user asks for full coverage, or release packaging needs a
   broad sweep.
3. If the change affects in-game UI or text, run the `Default In-Game Baseline`
   before UI-specific scenarios.
   If the scenario depends on generated terrain, joined clans, notifications,
   or available unit commands, create or load a fixed test save and reuse that
   save for failure reproduction and retesting. Do not reroll a new random
   start while chasing a screenshot failure. When a new random start exposes a
   tile, clan, notification, resource, or command issue, save that state before
   fixing or confirm an existing fixed save already reproduces it. Record the
   save name, load path, failure coordinates, and screenshot path with the test
   evidence.
4. Use computer-use when requested or useful. If XNA capture fails, immediately
   use the Win32 scripts from `operations.md`.
   When using the structured scenario runner, complete game/interface setup
   first, then call `tools\Invoke-AtGBlackBoxScenario.ps1` for the narrow
   scenario. The runner writes evidence to `.tmp\runs\<timestamp>-<scenario>`
   and emits `run-summary.json`.
5. Use fast UI-test discipline:
   - Do not rerun completed UI scenarios unless the touched source, font,
     config, DLL patch, or workflow change can affect that interface.
   - When a broad sweep fails, rerun only the failed coordinate/path first
     after the fix; rerun the broader sweep only if the failed path now passes.
   - Reuse the same launched game and open interface for related hovers.
   - Wait 700-1500 ms for routine hover tooltips, with a hard cap of 3 seconds.
   - Prefer cropped screenshots and contact sheets for text/tooltip review.
   - Rerun failed scenarios first; rerun broader sweeps only after the failure
     path passes.
6. Capture evidence for each failure:
   screenshot path, clicked/hovered coordinates, visible raw key/English/
   mojibake/layout problem, crash dialog, and relevant log timestamp. For a
   `HE'S DEAD, JIM` crash dialog, follow the crash-dialog handling procedure in
   `operations.md`: screenshot first, click OK to allow `Crash.AtGLog` to flush,
   then read the newly written log block as the authoritative stack/error text.
7. Record UI-test timing: clicks, hovers, screenshots, total duration, and the
   largest time sink.
8. If every selected test passes, hand off to `update-knowledge.md`.
   If the passed test was an incremental scenario, merge it into the matching
   full-regression interface scenario and remove the duplicate incremental
   entry during the knowledge update.
9. If any test fails, do not stop at reporting. Re-enter the loop:
   - Re-read `text-sources.md` and `crash-risks.md`.
   - Re-read `translation-style.md` when translating or judging visible English.
   - Reclassify the failed symptom and source risk.
   - Run `assess-and-fix.md`.
   - Run `package-and-install.md` to produce a fresh ready-build handoff.
   - Rerun the failed test against that installed build.
10. Repeat until tests pass or a stop condition is met.

## Failure Definition

Treat these as failures:

- Missing, stale, or failed ready-build handoff from `package-and-install.md`.
- Static validation or smoke test failure reported by the package workflow.
- Crash dialog or updated `Crash.AtGLog`.
- Raw `TEXT.*` key, enum name, unresolved tag, mojibake, or missing glyph.
- Safely localizable English text in an active scenario.
- Translation wording that violates the agreed historical 4X style when the
  source can be safely edited.
- Icon/font corruption.
- Layout defect that blocks reading or interaction.

## Stop Conditions

- The same failure repeats for three consecutive loops without new evidence or
  observable progress.
- The only plausible fix requires a logic-sensitive source and no isolated
  safety proof is available.
- The remaining issue is minor visual polish that does not block reading or
  interaction; record it under the relevant interface scenario.
- The test requires human judgment not available from screenshots.
- The agreed time, operation, or token budget is exhausted.

## Outputs

- Ready-build handoff status and pass/fail status for Active Focus Tests.
- Screenshots/log excerpts for any unresolved failure.
- Reasons for any visible English judged acceptable.
- UI-test timing and operation counts.
- A concise reason when the loop stops without passing.

## Knowledge Updates

When tests pass or a stop condition is reached, run `update-knowledge.md` before
final reporting.
