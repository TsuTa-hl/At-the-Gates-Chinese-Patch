# Workflow: Clean Workspace

## Purpose

Run once at the start of every task. Preserve reusable conclusions in a small
text handoff, then remove only known re-creatable temporary output.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/operations.md`
- `docs/agent/black-box-tests.md` only when a prior run may protect a fixed
  save, active scenario, or recovery record.

## Steps

1. Run the cleanup fixture before changing the cleanup tool:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Clear-AtGWorkspace.ps1
   ```

2. Audit candidates without changing files:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Clear-AtGWorkspace.ps1 -TaskId <task-id> -WhatIf
   ```

3. Review the proposed text handoff. It must retain scenario/save identity,
   coordinates, failure text, crash summary, timing, and conclusion before a
   disposable screenshot is removed.
4. Apply only after the audit is sensible:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Clear-AtGWorkspace.ps1 -TaskId <task-id> -Apply
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Compact-AtGEvidenceReferences.ps1 -HandoffId <task-id>
   ```

## Boundaries

The tool may operate only on approved `.tmp` categories. It must not remove
`source`, `patch`, `translations`, `.cache`, `.tools`, the game directory, or
saves. Active recovery data and current-task evidence remain protected.

`Clear-AtGEvidence.ps1` is a compatibility entry point; use
`Clear-AtGWorkspace.ps1` for new work.
