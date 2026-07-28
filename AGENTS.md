# At the Gates Chinese Patch Agent Guide

This project builds a Simplified Chinese patch for Jon Shafer's At the Gates.
Prefer startup stability over surface-level completeness.

## Global Rules

- Start every task with `docs/agent/workflows/cleanup-workspace.md` once. Reuse
  its text handoff for the rest of that task.
- Select a workflow from the dispatcher, then read only the files routed by
  `docs/agent/knowledge-index.md`. Do not preload the whole documentation set.
- Screenshot-discovered English, raw keys, mojibake, and tags must first be
  queried in `.cache/atg-catalog.sqlite`. Use the exact source catalogs under
  `docs/review/generated/` for patch operands. Persistent review views are not
  source data; generate a temporary CSV view with
  `docs/review/Generate-ReviewViews.ps1` only when filtering or sorting helps.
- Before changing composed, dynamic, or rich-text display text, query
  `translations/composite-text-rules.json` and reuse its `EntryPointId` and
  `RuleId`. Generate the temporary `Composite` CSV only when it helps navigation.
  Preserve concept keys, placeholders, hotkeys, colors, and recursive-hover structure.
- Use safety-first localization unless the user explicitly requests the
  fast-fail trial strategy.
- Carry timing through assess/fix, build, install, smoke, UI testing, and any
  retry.
- Every test session must update the relevant knowledge and text evidence
  before a retry or final report. A failure then returns to assess/fix.
- Do not stop at reporting a failure unless the selected workflow's stop
  conditions are met.

## Workflow Dispatcher

- Cleanup before every task: `docs/agent/workflows/cleanup-workspace.md`
- Diagnose and repair: `docs/agent/workflows/assess-and-fix.md`
- Build, refresh installation, and smoke: `docs/agent/workflows/package-and-install.md`
- Run selected black-box coverage and handle outcomes: `docs/agent/workflows/test-and-loop.md`
- Record every test-session outcome: `docs/agent/workflows/update-knowledge.md`

## Completion Rule

Before reporting completion, run the knowledge-update workflow for the latest
test session. Do not mark a UI scenario complete without current visual
verification or an explicitly recorded limitation.
