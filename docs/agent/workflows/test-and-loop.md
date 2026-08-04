# Workflow: Test and Loop

## Purpose

Run selected black-box coverage, create a text-first outcome, update the owning
knowledge, then either finish or return to repair.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/black-box-tests.md`
- Selected section of `docs/agent/black-box/interfaces.md`
- `docs/agent/operations/game-automation.md`

## Read after a Matching Failure

| Failure | Also read |
| --- | --- |
| Raw key, English, mojibake, unknown source | `text-sources.md`, then catalog/review topic |
| Dynamic ordering, broken link/highlight, recursive hover | composition-rule JSON, then filter the temporary Composite CSV by EntryPointId or source locator if needed |
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
3. Build and statically validate each affected scenario once, then run the
   authorized fixed-save replay. Never create a new random world merely to
   discover whether an unrelated surface might be wrong. Repeated random-world
   creation remains separately gated by explicit user confirmation and manual
   procedure confirmation.
4. If no replay was authorized, hand the prepared scenario to the user for
   manual execution. Otherwise collect cursor-marked screenshots and text-trace
   evidence from the approved fixed-save points.
5. If the user later supplies a manual crash result, use the crash procedure:
   record the screenshot and new `Crash.AtGLog` block as primary evidence.
6. Produce a session conclusion of `Stopped` (user-run pending) only when no
   replay was authorized; otherwise report the measured replay result.
7. **Run `update-knowledge.md` for every conclusion before doing anything
   else.** It records passing coverage, failures, limitations, and text evidence
   in their owning files.
8. If the conclusion is `Failed` from a user-provided manual result, return to
   assess/fix using the now-updated knowledge; do not autonomously retry the
   game.
9. Report the stopped/manual-pending result after the knowledge update.

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
