# Workflow: Assess and Fix

## Purpose

Use this workflow to diagnose and fix localization bugs, exposed variables,
mojibake, missing assets, crashes, unsafe English remnants, and layout defects.

## Read First

- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`
- `docs/agent/crash-risks.md`
- `docs/agent/black-box-tests.md`
- `docs/agent/operations.md` if reproducing, building, launching, clicking,
  hovering, or capturing screenshots is required.

## Inputs

- User report, screenshot, crash dialog, log excerpt, failing test output, or
  visible UI issue.
- Current patch source files and translation maps.
- Any screenshots or logs captured by `test-and-loop.md`.

## Steps

1. Classify the failure as crash, raw key, mojibake, untranslated English,
   missing asset, icon/font corruption, layout issue, or logic-sensitive text.
2. Locate the likely source in this order:
   `English.xml`, config XML, DLL `ldstr` catalog, UI DLL IL string, UI DLL
   complete UTF-16 string, UI DLL verified offset, Common DLL complete UTF-16
   string, static candidate export.
3. If the source is unknown, run static discovery and DLL catalog export before
   byte/string searches.
4. Patch only sources classified as safe display text.
5. When translating newly discovered safe English text, follow
   `translation-style.md` before writing to the selected source.
6. Review existing Chinese only when the source is safe and the change does not
   expand logic risk; do not force Common concepts, faction names, or dates for
   style consistency.
7. For UI DLL edits, prefer `hardcoded-ui-il-strings.json` when the visible
   text maps to a complete `ldstr` entry and the translation fits the existing
   `#US` heap entry. Use byte patches and offsets only as fallback.
8. For crash fixes, check `crash-risks.md` before touching Common concepts,
   faction names, dates, fonts, or ClanCard assets.
9. After edits, hand off to `package-and-install.md`. Do not update knowledge
   files before packaging unless the task is explicitly documentation-only.

## Stop Conditions

- The only plausible fix requires a logic-sensitive source without isolated
  regression coverage.
- The same failure has repeated through three fix/test cycles without new
  evidence.
- The issue requires human visual judgment that cannot be resolved from
  screenshots.
- The task budget or time limit is exhausted.

## Outputs

- Minimal source changes that address the classified failure.
- In-context notes for any newly discovered source, offset, term, style
  decision, acceptable English remnant, crash risk, or deferred layout issue.
- A specific test scenario to rerun through `test-and-loop.md`.

## Knowledge Updates

Do not update knowledge files mid-cycle. Carry findings forward through the
current context and command output. Final knowledge updates happen through
`update-knowledge.md` after the test loop passes or reaches a stop condition.
