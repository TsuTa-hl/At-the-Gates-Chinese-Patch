# Knowledge Routing Index

Use this index after `AGENTS.md`. Load the mandatory files for the selected
workflow, then only the conditionally routed topics. Generated databases and
rule JSON remain the facts; disposable CSV views support filtering and review.

## Workflow Routes

| Workflow | Always read | Read only when needed |
| --- | --- | --- |
| Cleanup | `operations.md` | `black-box-tests.md` when a fixed save or test run may be protected |
| Assess/fix | `text-sources.md`, `translation-style.md` | `catalog-review.md` for visible text; `managed-patching.md` for XML/DLL; `ui-source-map.md` for UI mapping; composition-rule JSON or a temporary filtered `Composite` CSV for dynamic text; crash-risk index plus its symptom topic; black-box interface and automation for reproduction; trial topic/state for explicit fast-fail work |
| Package/install | `operations/build-and-install.md`, `crash-risks.md` | text/managed topic after text-generation or rewrite changes; composition-rule JSON after dynamic/rich-text changes; crash-risk topic matching the changed subsystem |
| Test/loop | `black-box-tests.md`, selected interface topic, `operations/game-automation.md` | text/catalog/composite/style/crash topics only after a matching failure symptom |
| Update knowledge | latest test handoff and this index | only the owner files implicated by the result or source change |

## Topic Ownership

| Concern | Owner |
| --- | --- |
| PowerShell 5.1, quoting, paths, working directory, coordinate meaning | `operations.md` |
| Build/install/smoke | `operations/build-and-install.md` |
| Input/capture/crash procedure | `operations/game-automation.md` |
| Resource/network diagnostics | `operations/diagnostics.md` |
| Source priority and safety | `text-sources.md` |
| Catalog/review exports | `text-sources/catalog-review.md` |
| XML/DLL/tag precision | `text-sources/managed-patching.md` |
| UI source routing | `text-sources/ui-source-map.md` |
| Fast-fail batches | `text-sources/trial-localization.md` and `trial-localization-state.json` |
| Composition rules | `translations/composite-text-rules.json`; generate a temporary `Composite` CSV only when filtering context helps |
| Test strategy/state | `black-box-tests.md` |
| Interface coverage | `black-box/interfaces.md` and `black-box-scenarios.json` |
| Translation wording | `translation-style.md` |
| Crash and rollback index | `crash-risks.md` |
| Startup/XML/settings/religion/ClanCard detail | `crash-risks/startup-and-content.md` |
| Runtime font, atlas, icon, reload/OOM detail | `crash-risks/runtime-and-assets.md` |
| Managed rewrite and logic-sensitive detail | `crash-risks/managed-rewrites.md` |

## Generated Authorities

- `.cache/atg-catalog.sqlite`: discovered text occurrences and bindings.
- `translations/composite-text-rules.json`: editable composition-rule authority.
- `docs/review/generated/`: exact generated source catalogs for refresh and
  patch operands; not a human review view.
- `docs/review/Generate-ReviewViews.ps1`: creates disposable `KnownTexts`,
  `Composite`, and `Todo` CSV views under `.tmp/review-views` by default.
  Each reads SQLite and/or rule JSON directly; `Todo` does not read the other
  two views. These outputs are not source data and are not retained.
- `docs/agent/black-box-scenarios.json`: coordinate and scenario authority.
- `docs/agent/clan-trait-verification.json`: trait verification state.
