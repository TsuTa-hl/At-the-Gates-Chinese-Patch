# Workflow: Assess and Fix

## Purpose

Diagnose and repair localization, crash, layout, exposed-key, and safe display
issues. Complete task cleanup first and reuse its handoff.

## Read First

- `docs/agent/knowledge-index.md`
- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`

## Read by Symptom

| Symptom or change | Also read |
| --- | --- |
| Visible English, raw key, mojibake, unknown source | `text-sources/catalog-review.md` |
| XML, DLL, IL, tag, concept, or fallback patch | `text-sources/managed-patching.md` |
| Known UI surface | `text-sources/ui-source-map.md` |
| Dynamic order, rich text, highlighted link, recursive hover | `translations/composite-text-rules.json`; generate a temporary `Composite` CSV only when filtering context is needed |
| Startup/XML/settings/religion/ClanCard | `crash-risks.md`, then `crash-risks/startup-and-content.md` |
| Font, atlas, icon, reload/OOM | `crash-risks.md`, then `crash-risks/runtime-and-assets.md` |
| Common/UI/Game/ElfTools rewrite or logic-sensitive text | `crash-risks.md`, then `crash-risks/managed-rewrites.md` |
| Need reproduction or manual input | selected interface topic and `operations/game-automation.md` |
| Explicit fast-fail trial request | `text-sources/trial-localization.md` and `trial-localization-state.json` |

## Steps

1. Classify the report: crash, raw key, mojibake, untranslated display text,
   missing asset, icon/font issue, layout, or logic-sensitive text.
2. Query SQLite before direct source searches for screenshot-visible text. Use
   the generated catalog for exact DLL operands.
3. Choose the first safe source from the priority index. Do not treat lack of a
   screenshot as a reason to skip a discovered display candidate.
4. For a composition, find its `EntryPointId` and existing `RuleId`; reuse a
   complete display rule before adding any fragment. Before adding an
   entry-specific rule, identify every referenced text, its occurrence count,
   and whether one safe uniform translation works at every call site. Apply a
   safe uniform translation first. Add an entry rule only when a shared,
   still-untranslated reference cannot use one Chinese form across its proven
   callers; record that decision and the conflicting formats in the rule
   entry.
5. Translate safe text using the style guide. Preserve structural tags and do
   not broaden a logic-sensitive change for stylistic consistency.
6. Make the smallest source edit that covers the observed display path.
7. Hand the changed tree to package/install/smoke. Do not update knowledge
   before testing; retain findings in the current handoff.

## Fast-Fail Exception

Only an explicit user request enables trial batching. Follow the trial topic's
exact operands, batch limits, accepted/rejected state, and smoke-only scope.

## Stop Conditions

- The only plausible edit is logic-sensitive without isolated regression.
- The same failure has no new evidence after three repair/test cycles.
- Human visual judgment cannot be resolved with available evidence.
- Time or task budget ends.
