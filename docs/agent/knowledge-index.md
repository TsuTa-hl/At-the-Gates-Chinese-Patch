# Knowledge Routing Index

Use this index after `AGENTS.md`. Load the mandatory files for the selected
workflow, then only the conditionally routed topics. SQLite and rule JSON are
the facts. User review exports are not AI workflow input.

## Workflow Routes

| Workflow | Always read | Read only when needed |
| --- | --- | --- |
| Cleanup | `operations.md` | `black-box-tests.md` when a fixed save or test run may be protected |
| Assess/fix | `text-sources.md`, `translation-style.md` | `catalog-review.md` for visible text; `managed-patching.md` for XML/DLL; `ui-source-map.md` for UI mapping; composition-rule JSON queried by `EntryPointId`/`RuleId` for dynamic text; crash-risk index plus its symptom topic; black-box interface and automation for reproduction; safety registry for a previously rejected operand |
| Package/install | `operations/build-and-install.md`, `architecture.md` | text/managed topic after text-generation or rewrite changes; composition-rule JSON after dynamic/rich-text changes; crash-risk topic matching the changed subsystem |
| Release branch | `workflows/publish-release-branch.md`, `operations/build-and-install.md` | `architecture.md`, `crash-risks.md` after installer, uninstaller, or patch-artifact changes |
| Test/loop | `black-box-tests.md`, selected interface topic, `operations/game-automation.md` | text/catalog/composite/style/crash topics only after a matching failure symptom |
| Update knowledge | this index and changed-file list | latest test handoff only for a test result; owner files implicated by the changed fact |

## Topic Ownership

| Concern | Owner |
| --- | --- |
| PowerShell 5.1, quoting, paths, working directory, coordinate meaning | `operations.md` |
| Build/install/smoke | `operations/build-and-install.md` |
| Source/build/transaction/release data flow | `architecture.md` |
| Repository-wide refactor verification and scope limit | `current-status.md` |
| Recovery and common operational failures | `troubleshooting.md` |
| Input/capture/crash procedure | `operations/game-automation.md` |
| Resource/network diagnostics | `operations/diagnostics.md` |
| Source priority and safety | `text-sources.md` |
| Catalog operations and user review exports | `text-sources/catalog-review.md` |
| XML/DLL/tag precision | `text-sources/managed-patching.md` |
| UI source routing | `text-sources/ui-source-map.md` |
| Retired batch safety decisions | `text-sources/localization-safety.md` and `translations/localization-safety-registry.json` |
| Composition rules | `translations/composite-text-rules.json`; query `EntryPointId` and `RuleId` directly |
| Concept-link display labels | `translations/concept-key-translations.json`; query `Key` directly |
| Test strategy/state | `black-box-tests.md` |
| Interface coverage | `black-box/interfaces.md` and `black-box-scenarios.json` |
| Translation wording | `translation-style.md` |
| Crash and rollback index | `crash-risks.md` |
| Startup/XML/settings/religion/ClanCard detail | `crash-risks/startup-and-content.md` |
| Runtime font, atlas, icon, reload/OOM detail | `crash-risks/runtime-and-assets.md` |
| Managed rewrite and logic-sensitive detail | `crash-risks/managed-rewrites.md` |

## Generated Authorities

- `.cache/atg-catalog.sqlite`: AI catalog authority for exact occurrences,
  bindings, source paths, and locators. Query and maintain it through catalog
  tooling; do not use a user review export as an intermediate representation.
- `translations/composite-text-rules.json`: editable composition-rule authority.
- `translations/concept-key-translations.json`: static concept-link index with
  source labels and observed Chinese labels. Rebuild with
  `tools/Export-ConceptKeyTranslations.ps1` after changing its inputs; query
  `Key` directly before editing a concept-link display label.
- `docs/review/Generate-ReviewViews.ps1`: user-operated export tool for
  disposable `KnownTexts`, `Composite`, and `Todo` views under
  `.tmp/review-views`. AI maintains the script but never generates or reads its
  output.
- `docs/agent/black-box-scenarios.json`: coordinate and scenario authority.
- `docs/agent/clan-trait-verification.json`: trait verification state.
- `docs/agent/terrain-tooltip-boundary.json`: source-derived terrain/deposit/resource boundary and runtime reachability state; refresh with `tools/Build-TerrainTooltipBoundary.ps1` and never use it as a translation operand.
- `docs/agent/interface-localization-routes.json`: deterministic interface/surface/condition routing for the static progress audit.
- `docs/agent/interface-localization-progress.md`: progress formulas, isolated export protocol, and the latest static baseline.
