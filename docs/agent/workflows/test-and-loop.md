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
   change. Full regression remains opt-in.
3. Build each UI state once. For in-game tests, load the designated save from
   the main menu. A random discovery must save the exposed state before repair.
4. Execute related hovers/clicks in one process. Use stable scenario anchors,
   700-1500 ms hover waits, and a 3-second maximum.
5. On a crash, use the crash procedure: screenshot, dismiss dialog, read the
   new `Crash.AtGLog` block, and record the log as primary evidence.
6. Produce a session conclusion: `Passed`, `Failed`, or `Stopped`, with
   scenario/save, observed text, crash state, timing, and only necessary image
   references.
7. **Run `update-knowledge.md` for every conclusion before doing anything
   else.** It records passing coverage, failures, limitations, and text evidence
   in their owning files.
8. If the conclusion is `Failed`, return to assess/fix using the now-updated
   knowledge and repeat package/install/smoke -> test -> update knowledge.
9. If `Passed` or a documented stop condition applies, report the result after
   the knowledge update.

## Stop Conditions

- Only a logic-sensitive edit remains without isolated coverage.
- Three repair/test cycles yield no new evidence.
- The result requires unavailable human visual judgment.
- Time or task budget ends.
