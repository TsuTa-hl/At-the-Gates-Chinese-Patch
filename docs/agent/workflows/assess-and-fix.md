# Workflow: Assess and Fix

## Purpose

Use this workflow to diagnose and fix localization bugs, exposed variables,
mojibake, missing assets, crashes, unsafe English remnants, and layout defects.

## Read First

- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`
- `docs/agent/crash-risks.md`
- `docs/agent/black-box-tests.md`
- `docs/agent/trial-localization-state.json` if the user asks for trial or
  fast-fail localization.
- `docs/agent/spark-delegation.md` if this repository is being accessed
  directly by `GPT-5.3-codex-spark`.
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
2. For screenshot-visible English, raw keys, or untranslated UI text, query the
   generated SQLite catalog before static discovery, direct source searches,
   or patch edits:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search -CatalogText '<visible text>' -CatalogLimit 20
   ```

   Add `-CatalogSource '<source fragment>'` when the likely assembly or file is
   known. Use `docs/review/known-texts.md` only to inspect grouped source
   context, and `docs/review/known-texts.csv` only for human spreadsheet
   filtering. If a catalog match points at a DLL source, return to the exact
   generated catalog value in `docs/review/generated/*-ldstr-catalog.*` before
   writing an IL patch. If no catalog row matches, record that fact before
   continuing to discovery.
3. Locate the likely source in this order:
   SQLite catalog match, `English.xml`, config XML, DLL `ldstr` catalog, UI
   DLL IL string, UI DLL complete UTF-16 string, UI DLL verified offset, Common
   DLL complete UTF-16 string, static candidate export.
4. If the source is unknown, run static discovery and DLL catalog export before
   byte/string searches.
5. Patch only sources classified as safe display text.
6. When translating newly discovered safe English text, follow
   `translation-style.md` before writing to the selected source.
7. Review existing Chinese only when the source is safe and the change does not
   expand logic risk; do not force Common concepts, faction names, or dates for
   style consistency.
8. For UI DLL edits, prefer `hardcoded-ui-il-strings.json` when the visible
   text maps to a complete `ldstr` entry and the translation fits the existing
   `#US` heap entry. Use byte patches and offsets only as fallback.
9. For crash fixes, check `crash-risks.md` before touching Common concepts,
   faction names, dates, fonts, or ClanCard assets.
10. After edits, hand off to `package-and-install.md`. Do not update knowledge
   files before packaging unless the task is explicitly documentation-only.

## Trial Fast-Fail Strategy

Use this strategy only when the user explicitly asks to probe already
discovered display text beyond the safety-first policy.

1. Build a small batch from discovered display candidates with stable
   `MethodToken + ILOffset + Original` evidence and real Chinese translations.
   Missing UI screenshots or visual evidence alone is not a valid reason to
   skip an already discovered display candidate; use the smoke gate to quickly
   prove or reject the batch.
   Use the DLL catalog's exact `Value` for `Original`. Do not generate IL
   rewrite batch originals from `docs\review\known-texts.csv`, because that
   review table normalizes whitespace and newlines for human readability.
2. Read `docs/agent/trial-localization-state.json` before selecting a batch.
   Use it to avoid already accepted/rejected entries, preserve known catalog
   precision lessons, and choose the current batch size.
3. Prefer UI display strings first, then narrowly scoped Common/Game display
   fragments and narrowly scoped ElfTools helper-display strings. Do not
   include technical paths, IDs, enum keys, broad concept identifiers, faction
   names, dates, generated names, parser glue, or diagnostics in the same
   batch.
4. Default batch sizing:
   - UI exact-catalog candidates: start at 48 and cap at 64.
   - Common, Game, or ElfTools display candidates: start at 8 and cap at 16.
   - Logic-sensitive or historically risky candidates: 1 to 4 only.
   - If a failed batch contains more than one bad entry, halve the next batch
     size for that source class.
5. Run `tools\Invoke-AtGTrialLocalizationBatch.ps1` with the batch file. The
   tool appends the batch to normal rewrite maps, builds, installs, and runs
   `Test-GameLaunch.ps1 -IncludeNewGame` as its fast-fail smoke gate. If the
   batch fails, it bisects until failing single entries are isolated.
6. Keep only entries that the trial runner reports in `accepted.json` and whose
   batch is recorded in `docs/agent/trial-localization-state.json`. Leave
   failing, invalid-smoke, manually copied, or unrecorded entries out of the
   normal rewrite maps.
7. Carry accepted/rejected batch results forward to `update-knowledge.md` so
   `trial-localization-state.json` and `docs/review/known-texts.csv` remain
   synchronized.
8. A trial pass only proves build, install, startup, and explicitly requested
   new-game smoke safety. It does not prove wording, layout, hover coverage,
   fixed-save loading, or all UI paths.

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
