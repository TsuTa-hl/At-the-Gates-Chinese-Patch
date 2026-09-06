# Workflow: Test and Loop

## Purpose

Run selected black-box coverage, create a text-first outcome, update the owning
knowledge, then either finish or return to repair.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/black-box-tests.md`
- Selected section of `docs/agent/black-box/interfaces.md`
- `docs/agent/operations/game-automation.md`
- `docs/agent/operations/debug-console.md` only for an uncalibrated target,
  console-assisted diagnosis, or a user-authorized manual recording

## Read after a Matching Failure

| Failure | Also read |
| --- | --- |
| Raw key, English, mojibake, unknown source | `text-sources.md`, then catalog-operations topic |
| Dynamic ordering, broken link/highlight, recursive hover | composition-rule JSON queried directly by `EntryPointId` or source locator |
| Translation quality | `translation-style.md` |
| Startup/XML/settings/religion/ClanCard crash | `crash-risks.md`, then `crash-risks/startup-and-content.md` |
| Font, atlas, icon, missing glyph, reload/OOM | `crash-risks.md`, then `crash-risks/runtime-and-assets.md` |
| Managed rewrite, concept link, logic-sensitive display | `crash-risks.md`, then `crash-risks/managed-rewrites.md` |
| XML/DLL patch path | `text-sources/managed-patching.md` |

## Session Steps

1. Confirm a current successful package/install/smoke handoff. Otherwise run
   package/install first.
2. Select Active Focus plus only the interface scenarios affected by the
   change. Full regression remains opt-in. If the user authorizes a designated
   fixed-save replay, execute only that selected scenario.
3. Skip console setup for a point with current calibration. For an uncalibrated
   screenshot or named runtime-state question, run the console-assisted target
   triage owned by `operations/game-automation.md`, then complete its
   cursor-marker calibration gate before making text assertions.
4. Build and statically validate each affected scenario once, then run the
   authorized fixed-save replay. Use structured harness actions as replay
   authority; console output and recordings remain discovery inputs only.
5. Never create a new random world merely to discover whether an unrelated
   surface might be wrong. Repeated random-world creation remains separately
   gated by explicit user confirmation and manual procedure confirmation.
6. If no replay was authorized, hand the prepared scenario to the user for
   manual execution. Otherwise collect cursor-marked screenshots and text-trace
   evidence from the approved fixed-save points.
7. If the user later supplies a manual crash result, use the crash procedure:
   record the screenshot and new `Crash.AtGLog` block as primary evidence.
8. Produce a session conclusion of `Stopped` (user-run pending) only when no
   replay was authorized; otherwise report the measured replay result.
9. **Run `update-knowledge.md` for every conclusion before doing anything
   else.** Use its knowledge-maintenance steps to incorporate passing coverage,
   failures, limitations, and text evidence into their owning files.
10. If the conclusion is `Failed`, return to assess/fix using the now-updated
   knowledge unless a stop condition applies. For a user-provided manual
   result, do not autonomously retry the game.
11. Report the stopped/manual-pending result after the knowledge update.

## User-confirmed exploratory boundary

Execution of workflows that create random worlds remains disabled by default.
If the user explicitly re-authorizes such a workflow, follow only the
requested procedure and do not autonomously tune coordinates, add coverage,
change stop criteria, or iterate on it.

## Stop Conditions

- Only a logic-sensitive edit remains without isolated coverage.
- Three repair/test cycles yield no new evidence.
- The result requires unavailable human visual judgment.
- Time or task budget ends.
