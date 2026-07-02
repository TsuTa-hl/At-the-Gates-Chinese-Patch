# At the Gates Chinese Patch Agent Guide

This project builds a Simplified Chinese patch for Jon Shafer's At the Gates.
Prefer startup stability over surface-level completeness.

## Global Rules

- Start by selecting the matching workflow below and reading every file it
  lists before making changes.
- Default cycle for repair work:
  assess/fix -> package/install/smoke -> test/loop -> update knowledge.
- Default localization policy is safety-first and black-box driven. When the
  user explicitly asks for trial localization, use the fast-fail batch strategy
  in `docs/agent/workflows/assess-and-fix.md`.
- If testing fails, return to assess/fix and repeat the cycle. Do not add a
  separate pre-test knowledge-update phase unless the user explicitly asks for
  documentation-only maintenance.
- Carry a timing summary through each workflow cycle: assess/fix, build,
  install, smoke, UI test, and failure-loop rework.
- A failed static check, smoke test, Active Focus Test, screenshot inspection,
  crash, mojibake, raw key, or safely localizable English string must enter the
  loop in `docs/agent/workflows/test-and-loop.md`.
- Do not stop at reporting a failure unless that workflow's stop conditions are
  met.
- Keep this file short. Put operations, text-source rules, crash risks, test
  scenarios, and translation style in the topic files under `docs/agent/`.

## Workflow Dispatcher

- Assess and fix localization, crash, layout, exposed-key, or translation-style
  issues: `docs/agent/workflows/assess-and-fix.md`
- Build, package, install, or run the smoke gate for the patch:
  `docs/agent/workflows/package-and-install.md`
- Run UI tests, inspect screenshots, or handle failed tests after the package
  workflow has produced an installed build:
  `docs/agent/workflows/test-and-loop.md`
- After tests pass or stop, update project knowledge:
  `docs/agent/workflows/update-knowledge.md`

## Topic Files

- Runtime operations and manual automation:
  `docs/agent/operations.md`
- Text source safety and extraction rules:
  `docs/agent/text-sources.md`
- Crash and rollback risk register:
  `docs/agent/crash-risks.md`
- Translation tone, terminology, UI wording, and display exceptions:
  `docs/agent/translation-style.md`
- Active, deferred, and completed black-box UI scenarios:
  `docs/agent/black-box-tests.md`
- Trial localization batch state for agent/script resume:
  `docs/agent/trial-localization-state.json`

## Completion Rule

Before reporting completion, run `docs/agent/workflows/update-knowledge.md`.
Do not mark a UI scenario completed unless the latest installed build was
visually tested or the limitation is explicitly recorded.
