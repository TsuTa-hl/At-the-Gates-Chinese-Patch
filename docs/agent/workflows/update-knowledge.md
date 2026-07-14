# Workflow: Update Knowledge

## Purpose

Use this workflow after tests pass, or after the test loop reaches a documented
stop condition, to keep agent guidance current and compact. Do not use it as a
pre-test synchronization phase during the normal repair cycle.

## Read First

- `AGENTS.md`
- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`
- `docs/agent/crash-risks.md`
- `docs/agent/black-box-tests.md`
- `docs/agent/trial-localization-state.json` if trial localization batches
  were selected, run, accepted, rejected, or deferred.
- `docs/agent/spark-delegation.md` if the current cycle was run directly by
  `GPT-5.3-codex-spark` or produced higher-model review items.
- The workflow files used in the current cycle.

## Inputs

- Final ready-build and test status from `test-and-loop.md`.
- New sources, offsets, risks, screenshots, or deferred UI findings from the
  current work cycle.

## Steps

1. Update `AGENTS.md` only for global rules, workflow dispatch, or workflow
   gate changes.
2. Update `text-sources.md` for new text files, DLL strings, offsets, alias
   rules, safety classifications, or acceptable source priorities.
3. Update `translation-style.md` for new recurring terms, tone rules,
   acceptable English remnants, or style exceptions.
4. Update `crash-risks.md` for new crashes, missing asset workarounds,
   logic-sensitive classes, or rollback rules.
5. Update `black-box-tests.md`:
   - Move current scenarios into `Active Focus Tests` while they are failing.
   - Move fully passed scenarios into `Completed / Deferred UI Tests By
     Interface`.
   - For machine-readable cases, keep known and passed coverage under
     `FullRegression` in `docs/agent/black-box-scenarios.json`.
   - Add new screenshot/reproduction reports to `Incremental` first. After
     they pass, merge them into the matching `FullRegression` interface
     scenario, deduplicate by point ID, and remove the incremental entry.
   - Record minor visual-polish remnants under the relevant interface scenario
     rather than using a separate layout queue.
   - Keep `Default In-Game Baseline` as an on-demand baseline, not a global
     gate.
   - Record any new fixed-save scenario, including save name, load path,
     interface, coordinates, and screenshot/contact-sheet evidence.
   - For tile and clan scenarios found from a random start, record whether the
     state was saved before fixing or which existing fixed save reproduces it.
   - For crashes, record the screenshot path, triggering action, whether the
     dialog was acknowledged to flush `Crash.AtGLog`, and the relevant latest
     log excerpt or reason the log was unavailable.
6. Record timing lessons when they affect future workflow choices:
   - Assess/fix duration.
   - Build duration and whether font cache hit.
   - Install duration, including whether uninstall-before-install occurred.
   - Smoke duration.
   - UI test duration and screenshot/hover count.
   - Failure-loop rework duration.
7. If trial localization ran, update `docs/agent/trial-localization-state.json`
   before regenerating review output:
   - Add each batch path, source scope, input count, accepted count, rejected
     count, and final status.
   - Add rejected single entries with assembly, `MethodToken`, `ILOffset`,
     exact `Original`, failure reason, and retry condition.
   - Record catalog-precision failures separately from unsafe text failures.
   - Update the next batch-size guidance only when observed failure density
     changes.
   - Confirm normal rewrite maps contain no entries from rejected batches,
     invalid-smoke batches, or batch files missing from
     `trial-localization-state.json`.
   - Remove root-level scratch files created during candidate selection; keep
     temporary probes under `.tmp` only.
8. Regenerate the known-text review outputs before final reporting when
   translation maps, static candidates, DLL catalogs, or trial-localization
   results changed:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-KnownTextReview.ps1
   ```

   Then validate the review export shape:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-KnownTextReviewExport.ps1
   ```

   The exporter must rebuild `.cache\atg-catalog.sqlite` as the primary
   non-deduplicated occurrence store, then emit
   `docs\review\known-texts.md` as an AI/context view and
   `docs\review\known-texts.csv` as a human spreadsheet view. Both files
   contain source, kind, original, translation, status, compact
   review state, compact reason code, safety, notes, and locators.
   `ReviewState` is one of `Translated`, `NeedsTrial`, `Skipped`,
   `RecheckedSkipped`, or `Rejected`; `Skipped` means not revisited in the
   current skip recheck pass, while `RecheckedSkipped` means re-reviewed and
   intentionally kept out of trial localization. `ReasonCode` is a short
   category for skipped or rejected rows rather than a long prose failure
   explanation. The committed review outputs must use the default
   non-deduplicated output so repeated DLL `ldstr` occurrences and repeated XML
   nodes keep their own locators. `Export-KnownTextReview.ps1` rebuilds stable
   discovery inputs under `docs\review\generated\`; do not rely on `.tmp`
   files for the committed review files. Query SQLite through
   `Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search` first when
   matching screenshot text; use Markdown for grouped context and CSV only for
   human table review or spreadsheet filtering.
9. Update `docs\review\project-inventory.md` when files, generated artifacts,
   test evidence policy, or cleanup decisions change.
10. If Spark handled part of the work directly, record only durable outcomes:
   accepted batches, rejected singles, and higher-model review items. Spark
   does not handle screenshot/image-driven incremental localization; those
   remain in the main workflow. Do not copy long Spark reasoning into knowledge
   files.
11. Keep `AGENTS.md` short. Put operational details in `operations.md`, workflow
   steps in `docs/agent/workflows/`, and domain facts in the topic files.

## Stop Conditions

- Do not mark a scenario completed unless the latest installed build was
  visually tested or the limitation is explicitly recorded.
- Do not remove a risk unless a newer regression run proves the workaround is no
  longer needed.

## Outputs

- Updated agent documentation.
- Clear final status: passed, stopped by risk, stopped by budget, or deferred
  with an explicit interface/scenario reason.

## Knowledge Updates

This workflow is the knowledge update. If new facts are discovered while editing
docs, place them in the narrowest relevant knowledge file rather than expanding
`AGENTS.md`.
