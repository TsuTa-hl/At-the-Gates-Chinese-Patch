# Text Source Safety and Priority

Use this index to choose a safe source. It intentionally does not contain every
candidate, method, or historical experiment.

## Source Priority

1. `source/English.original.xml` -> `translations/zh-CN.json` ->
   `patch/Content/Text/English.xml`
2. Stable config XML node -> config-node translation map
3. UI display `ldstr` -> exact UI IL rewrite map
4. Runtime final-display map -> `translations/runtime-display-strings.json`
5. Verified byte/offset fallback only when a more structural path cannot cover
   the same visible string

`English.xml` must begin with `<english>` and omit an XML declaration.

## Safety Classes

- `DisplaySafe`: stable display text with isolated patch evidence.
- `DisplayComposite`: dynamic or rich text; use a complete template or final
  display rule, not a disconnected word fragment.
- `LogicSensitive`: names, dates, identifiers, or text coupled to behavior;
  patch only with isolated regression coverage.
- `Technical`: paths, diagnostics, parser glue, metadata, and other text that
  is not ordinary player-facing localization.

## Conditional Topics

- SQLite catalog, review exports, and static discovery:
  `docs/agent/text-sources/catalog-review.md`
- XML/DLL patch precision, tags, concepts, and rich-text structure:
  `docs/agent/text-sources/managed-patching.md`
- Known UI surfaces and likely sources:
  `docs/agent/text-sources/ui-source-map.md`
- Explicit fast-fail batches and resume state:
  `docs/agent/text-sources/trial-localization.md`
- Dynamic composition inventory and reusable Rule IDs:
  `translations/composite-text-rules.json`; generate a temporary `Composite`
  CSV through `docs/review/Generate-ReviewViews.ps1` only when needed
