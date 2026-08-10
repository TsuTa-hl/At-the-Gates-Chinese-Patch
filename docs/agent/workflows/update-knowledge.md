# Workflow: Update Knowledge

## Purpose

Run whenever a durable project fact changes: source location, patch behavior,
composition rule, safety decision, terminology, operational procedure, or
test evidence. Keep that fact compact and in its single owning record.

A test session always invokes this workflow before a retry or final report,
but testing is only one input. This is not a test-results log, a pre-test
phase, or a replacement for the owner's factual record.

## Read First

- `docs/agent/knowledge-index.md`
- The changed-file list and the evidence for the changed fact
- The latest test-session handoff only when the trigger is a test session

## Read by Trigger or Change

| Trigger/change | Update/read owner |
| --- | --- |
| Scenario passed, failed, moved, or limited | `black-box-tests.md`, selected interface topic, scenario JSON, trait state if relevant |
| New source, candidate, binding, or exact operand | `text-sources.md` plus the matching source topic and SQLite catalog operation |
| Composition/rich-text rule | `translations/composite-text-rules.json`, queried directly by `EntryPointId` and `RuleId` |
| Crash, asset, font, settings, load lifecycle | `crash-risks.md`, its matching detail topic, and needed operations topic |
| Terminology or wording decision | `translation-style.md` |
| Historical rejected operand | `text-sources/localization-safety.md` and `localization-safety-registry.json` |
| Cleanup/evidence retention | cleanup workflow handoff only |

## Steps

1. Identify the changed fact and its authoritative evidence: source/catalog
   record, changed implementation, user decision, or test handoff.
2. Update the smallest owning machine/document record; do not create a second
   history of the same fact in this workflow.
3. When the input is a test result, move passed incremental coverage into its
   existing owner. For a failure, record the observed final format and the
   candidate source or explicit lack of match. Preserve `EntryPointId` and
   `RuleId` for composed text.
4. Rebuild and validate `translations/concept-key-translations.json` after a
   change to either of its static inputs.
5. Refresh the SQLite catalog only when its source data changed. Do not generate
   or read user review exports; users may export them independently. Preserve
   manual `LocalizedFormat`, Rule ID, status, and notes.
6. Replace long screenshot references with a cleanup handoff summary once the
   visible defect is textualized. Keep an image only for an unresolved visual
   defect that cannot be described reliably.
7. Keep `AGENTS.md` and the knowledge index as routing-only documents. Put new
   facts into their single owner, not into multiple workflow files.
8. Do not create a topic document for a one-off text surface or incident. Keep
   its exact SQLite locator and current-task handoff instead.
9. Do not add an individual localization repair or user-led manual-test status
   to `current-status.md`; that file is reserved for repository-wide refactor
   verification. Keep the item in its current handoff or scenario owner.
10. If a test conclusion failed, hand the updated knowledge back to assess/fix.
   Otherwise continue with the workflow or final report that triggered this
   knowledge update.
