# Workflow: Update Knowledge after Testing

## Purpose

Run after **every** test-session conclusion: pass, failure, or stop. This is
not a pre-test phase. It converts disposable visual evidence into compact,
owned rules before a retry or final report.

## Read First

- `docs/agent/knowledge-index.md`
- The latest test-session handoff and changed-file list

## Read by Result

| Result/change | Update/read owner |
| --- | --- |
| Scenario passed, failed, moved, or limited | `black-box-tests.md`, selected interface topic, scenario JSON, trait state if relevant |
| New source, candidate, binding, or exact operand | `text-sources.md` plus the matching source topic and catalog/review export |
| Composition/rich-text rule | `translations/composite-text-rules.json`, plus a temporary `Composite` CSV only when needed |
| Crash, asset, font, settings, load lifecycle | `crash-risks.md`, its matching detail topic, and needed operations topic |
| Terminology or wording decision | `translation-style.md` |
| Trial result | trial topic and `trial-localization-state.json` |
| Cleanup/evidence retention | cleanup workflow handoff only |

## Steps

1. Record the test conclusion, setup/save, text result, crash summary, timing,
   and limitation in the smallest owning machine/document record.
2. Move a passed incremental point into its existing interface coverage; do not
   duplicate it as a separate historical checklist.
3. For a failure, record the observed final format and the candidate source or
   explicit lack of match. If composed, preserve `EntryPointId` and `RuleId`.
4. Refresh source catalogs only when their source data changed. Generate temporary
CSV review views with `Generate-ReviewViews.ps1` only when they are needed for
   inspection or validation. Preserve manual
   `LocalizedFormat`, Rule ID, status, and notes.
5. Replace long screenshot references with a cleanup handoff summary once the
   visible defect is textualized. Keep an image only for an unresolved visual
   defect that cannot be described reliably.
6. Keep `AGENTS.md` and the knowledge index as routing-only documents. Put new
   facts into their single owner, not into multiple workflow files.
7. If the conclusion failed, hand the updated result back to assess/fix. If it
   passed or stopped, hand the updated result to the final report.
