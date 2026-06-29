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
7. Keep `AGENTS.md` short. Put operational details in `operations.md`, workflow
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
