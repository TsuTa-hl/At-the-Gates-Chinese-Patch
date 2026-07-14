# GPT-5.3-codex-spark Direct-Run Guide

## Purpose

Use this file when the project is opened directly in a separate
`GPT-5.3-codex-spark` conversation. Spark is suitable for bounded mechanical
localization work: review-table filtering, trial batch generation, safe-source
translation edits, and existing script execution.

Spark is not the escalation model for ambiguous visual reasoning, new patch
architecture, crash analysis, UI/layout code changes, unknown text-source
discovery, or screenshot/image-driven localization. Spark does not support
image input in this project workflow. When those appear, Spark should record a
precise stop reason and leave the issue for the main workflow or a
higher-capability model.

## Read First

Every Spark run must start by reading:

- `AGENTS.md`
- `docs/agent/spark-delegation.md`
- The workflow matching the task:
  - `docs/agent/workflows/assess-and-fix.md`
  - `docs/agent/workflows/package-and-install.md`
  - `docs/agent/workflows/test-and-loop.md`
  - `docs/agent/workflows/update-knowledge.md`
- Topic files required by that workflow.

For trial localization, also read:

- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`
- `docs/agent/trial-localization-state.json`
- `docs/review/known-texts.md`
- `docs/review/known-texts.csv` only when spreadsheet-style filtering is
  needed.
- `docs/review/generated/*-ldstr-catalog.csv` or `.json` as needed.

## Global Spark Rules

- Use existing scripts and known source maps. Do not invent a new patch route.
- Do not run full black-box regression unless the user explicitly asks.
- Do not skip discovered display text only because no screenshot evidence
  exists. Use trial fast-fail or record a concrete risk reason.
- Spark must not handle screenshot/image-driven incremental localization. If a
  request depends on reading a screenshot, hover image, or visual UI state,
  stop and record a higher-model/main-workflow review item. If the user or a
  higher-capability model has already extracted exact text and supplied source
  rows, Spark may handle the resulting text-only batch task.
- For DLL IL rewrite entries, use exact catalog `Value + MethodToken +
  ILOffset`. Do not use the normalized `Original` column from
  `docs/review/known-texts.md` or `docs/review/known-texts.csv` as a patch
  original.
- Preserve tags, variables, placeholders, hotkeys, file paths, URLs, and
  parser markers.
- Do not bulk-patch Common concept terms, dates, month/season text, faction
  names, city names, generated names, external online flows, settings-file
  comments, or raw parser keys.
- Do not trial-localize `AtTheGatesCommon.ns_Text.Text.ConvertTags`,
  bracket-only parser-like tokens such as `[Active]` or `[HILL:S]`, or any
  entry whose original/translation contains the Unicode replacement character
  `U+FFFD`. These are rejected by the trial batch runner.
- Do not trial-localize `AtTheGatesCommon.ns_GlobalSystems.UserSetting_*`
  description/comment strings or `AtTheGatesGame.DebugConsoleNS.DebugConsole`
  command/help strings.
- Only entries accepted by `Invoke-AtGTrialLocalizationBatch.ps1` may remain in
  the normal rewrite maps. Rejected entries, invalid-smoke entries, and entries
  from batch files that are not recorded in `trial-localization-state.json`
  must be removed before handoff.
- Do not leave scratch files in the repository root. Temporary CSV/PS1 probes
  belong under `.tmp` and are not part of the deliverable.
- On crash dialogs, screenshot first, click OK, then read the newest
  `Crash.AtGLog` block. If the crash cause is not a directly isolated trial
  entry, stop and record an upgrade-required item.
- Keep changes narrow. Do not edit UI/game logic code.

## Task A: Recheck Skipped Text and Trial Localize

Spark can run this task directly.

### Candidate Selection

1. Refresh the review table:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-KnownTextReview.ps1
   ```

2. Prefer `ReviewState = Skipped`, because those rows have not been revisited
   in the current skip recheck pass.
3. Use `ReviewState = RecheckedSkipped` only when the user explicitly asks to
   retry previously rechecked skipped text.
4. Keep skipping rows whose concrete reason is:
   - technical/internal log, exception, assertion, diagnostic, or debug text;
   - file path, resource ID, DLL/XML/XNB/asset path, or raw parser key;
   - semantic-free punctuation, format suffix, or tag-conversion token;
   - `AtTheGatesCommon.ns_Text.Text.ConvertTags` entries and bracket-only
     parser-like tags;
   - logic-sensitive date/month/season, faction/city/generated-name text;
   - external login, challenge, forum, URL, or online-flow text;
   - settings-file comments or text known to corrupt `Settings.xml`.
5. Treat likely player-visible UI phrases, tooltip fragments, notification
   fragments, command text, victory/help descriptions, and clan/tile display
   fragments as candidates.

### Batch Sizes

- UI exact-catalog candidates: start at 32, may grow to 48.
- Common/Game/ElfTools display candidates: start at 8, may grow to 16.
- Historically risky or ambiguous candidates: 1 to 4.
- If a failed batch isolates more than one bad entry, halve the next batch size
  for that source class.

### Execution

1. Build a batch JSON under `translations/`.
2. Use historical 4X translation style from `translation-style.md`.
3. Run the batch through the existing trial runner. It performs safety
   validation before build/install/smoke:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGTrialLocalizationBatch.ps1 -BatchJson .\translations\<batch>.json
   ```

4. After any accepted batch, run the map risk guard:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-IlRewriteMapRisk.ps1
   ```

5. Also run the batch-safety guard before handoff:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-TrialLocalizationBatchSafety.ps1
   ```

6. If the batch passes, keep accepted entries and regenerate
   `docs/review/known-texts.csv`.
7. If the batch fails, allow the existing script to bisect. Record rejected
   single entries with exact assembly, method token, IL offset, original, and
   failure reason.
8. Before finishing, compare map additions against accepted batch results. Any
   entry without accepted batch evidence is a higher-model review item, not a
   committed map change.

### Spark Stop Conditions

- A failure cannot be bisected to a specific entry.
- The likely fix is a Common concept, date, faction, city, settings-file, or
  other logic-sensitive source.
- A build or smoke failure is not explained by the batch output.
- New text-source discovery or patch-tool changes are needed.
- A meaningful pass over candidate classes is complete and remaining skipped
  rows all have concrete skip reasons.

## Spark Must Stop for Higher-Model Review When

- The request requires reading or interpreting a screenshot, image, hover
  capture, UI layout, or visual state.
- Extracted text does not match known sources or generated catalogs.
- Multiple plausible sources exist and risk differs by source.
- A new text-containing file must be discovered.
- UI layout, renderer, font metrics, or game logic code must be changed.
- A crash, memory issue, missing asset, or unstable fixed-save reproduction
  appears.
- Two fix/test loops fail without a new specific cause.

## Prompt Template for a Separate Spark Conversation

Use this structure when starting a new Spark conversation:

```text
Model: GPT-5.3-codex-spark
Task: recheck-skipped-text
Goal: <one sentence>
Repository: C:\Users\98538\Documents\AtTheGateChinese

Read first:
- AGENTS.md
- docs/agent/spark-delegation.md
- <workflow/topic files>

Inputs:
- <known-text rows, catalog rows, or batch scope>

Allowed actions:
- <specific files/scripts Spark may touch>

Forbidden actions:
- Do not change UI/game logic.
- Do not bulk-patch logic-sensitive text.
- Do not run full black-box regression unless explicitly requested.

Stop and record higher-model review item if:
- <task-specific upgrade conditions>

Expected output:
- Changed files
- Batch IDs
- Test commands and results
- Review table counts
- Higher-model review items
```

## Spark Result Format

Spark should finish with:

```text
Status: passed | stopped-higher-model-required | stopped-budget | failed
Changed files:
- <path>
Batches:
- <id and result>
Tests:
- <command>: <pass/fail/not run>
Review table:
- Translated=<n>, NeedsTrial=<n>, Skipped=<n>, RecheckedSkipped=<n>, Rejected=<n>
Higher-model review required:
- <item, evidence, why Spark stopped>
```
