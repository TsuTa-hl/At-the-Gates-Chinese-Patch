# Text Source Safety and Priority

Use this routing index to choose an exact display source. It is not a record of
experiments or a substitute for the source catalogs.

## Source priority

1. `source/English.original.xml` → `translations/zh-CN.json` → generated
   `patch/Content/Text/English.xml`
2. Stable config XML node → ID/XPath-scoped config-node map
3. UI display `ldstr` → exact UI IL rewrite (`MethodToken + ILOffset + Original`)
4. Final runtime display → `translations/runtime-display-strings.json`
5. Verified byte/offset fallback only when a structural route cannot cover the
   same visible text

For composed, dynamic, or rich text, first read
`translations/composite-text-rules.json` and preserve its `EntryPointId`,
`RuleId`, tags, placeholders, hotkeys, concept keys, colors, and recursive
hover structure.

## Safety classes

- `DisplaySafe`: isolated player-facing text with an exact route.
- `DisplayComposite`: build a complete template or final-display rule; never
  globally replace a disconnected grammar fragment.
- `LogicSensitive`: names, dates, identifiers, serialization, or behavior-
  coupled text; require isolated regression evidence.
- `Technical`: diagnostics, paths, parser glue, metadata, and non-display text.

## Stable rules

- `English.xml` starts with `<english>` and has no XML declaration.
- Preserve XML IDs, XPath identity, concept keys, raw tags, and placeholders.
- Existing saves can carry prior display names; prefer the runtime display map
  over altering logic-facing identifiers.
- `UserSetting_*` descriptions are not managed-string patch targets: their
  serialized non-ASCII comments can break `Settings.xml`.
- Never use a user review export as an IL operand. Query
  `.cache/atg-catalog.sqlite` directly and retain the exact `Original`,
  `SourceFile`, and `Locators` values returned by the catalog.

## Conditional topics

- Direct catalog operations and user review exports: [catalog-review.md](text-sources/catalog-review.md)
- XML/DLL/tag precision: [managed-patching.md](text-sources/managed-patching.md)
- UI surface routing: [ui-source-map.md](text-sources/ui-source-map.md)
- Canonical retired-batch decisions: [localization-safety.md](text-sources/localization-safety.md) and `translations/localization-safety-registry.json`

Do not create a conditional topic for one resource, screen, event, string, or
incident. Query SQLite for the exact source and keep task-specific evidence in
the current handoff; add documentation only when a rule, schema, or routing
decision is reusable across multiple future tasks.
