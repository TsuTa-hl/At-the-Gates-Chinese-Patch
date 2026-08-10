# At the Gates Chinese Patch Agent Guide

This project builds a Simplified Chinese patch for Jon Shafer's At the Gates.
Prefer startup stability over surface-level completeness.

## Global Rules

- Start every task with `docs/agent/workflows/cleanup-workspace.md` once. Reuse
  its text handoff for the rest of that task.
- Select a workflow from the dispatcher, then read only the files routed by
  `docs/agent/knowledge-index.md`. Do not preload the whole documentation set.

## Workflow Dispatcher

- Diagnose and repair: `docs/agent/workflows/assess-and-fix.md`
- Build, refresh installation, and smoke: `docs/agent/workflows/package-and-install.md`
- Run selected black-box coverage and handle outcomes: `docs/agent/workflows/test-and-loop.md`
- Maintain durable project knowledge: `docs/agent/workflows/update-knowledge.md`

## Completion Rule

The selected workflow owns its required evidence, handoff, retry, and stop
conditions. Report only the resulting outcome and any explicit limitation.
