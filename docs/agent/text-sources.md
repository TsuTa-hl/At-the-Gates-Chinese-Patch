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

For a full raw config snapshot used by an ID-scoped config-node patch, treat
the snapshot as source inventory, not as proof that every node is localized.
Only the declared IDs in the config-node map are active patch operands. Their
Composite entries must bind to `xml-existing-translation` after the build;
unlisted nodes remain visible in the static source catalog for later review.

`English.xml` must begin with `<english>` and omit an XML declaration.

The fixed playable tribe IDs are defined in `Factions.original.xml`. Preserve
their logic-facing `<name>` and `city/name` values: `Screen_ChooseFaction.Update`
derives `FACTION_` plus `Substring(4)` from the button text. Localize those
names through the runtime display map and retain the FACTION concept fallback.
`FACTION_NEUTRALS/duplicateFactionNamesList/name` adds 57 neutral tribe names;
keep their source order when patching the indexed nodes. New worlds can read
those patched config values, but existing saves carry the original display
names; the runtime map therefore also contains the 57 full names and split
tooltip fallbacks, each with a durable KnownText locator.
Standalone diplomacy connectors such as `from` belong to the runtime display
map or an exact UI rewrite, not to the source catalogs.

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

## Recent Static Binding

The 2026-08-03 UBL-TVF forage-tooltip repair keeps the two residual connectors
as method-scoped UI operands in `AtTheGatesUI.ns_InGame.SelectionPanel` /
`AddButton_Forage` (`0x06000389`, IL offsets 944 and 1013): ` will ` -> `将`
and `This ` -> `该`. The `become obsessed with the idea of` case was corrected
at its config source on 2026-08-06: `Content/Config/Misc/Intensities.xml`,
`INTENSITY_OBSESSED` / `description`, whose actual source format is
`[COLOR:BAD-RED]become obsessed[/COLOR] with the idea of`. The colour tag
splits the phrase, so an uninterrupted runtime-map entry cannot match this
form. `GAME.BuildDescription_Desire` (`0x06001732`) resolves the intensity
description into the displayed desire clause. The config-node map now emits
`[COLOR:BAD-RED]会痴迷[/COLOR]于`; its Composite entry point is
`xml:source/Content/Config/Misc/Intensities.original.xml:c606cffb9531ea63`
under `xml-existing-translation`. The previous runtime-map entries remain only
as fallbacks for any separate uninterrupted display path. The refreshed Composite authority contains
11,914 entries, 15 rules, and 293 runtime-map bindings. This was a static-only
repair; the user will perform the visual replay.

The priority continuation fixed a rich-text display-path omission rather than
adding a global word replacement. `DisplayStringLocalizer` now preserves
bracketed tags and applies plain fragments only to text outside those tags,
while rich fragments handle concept-linked text. The same source-scoped pass
covers Relationship Level delta reasons, including both exact `less.)` and
`less).` punctuation variants of the finite border-distance family, and
diplomacy-operation keywords, and
the UBL-TVF residual group (`Bandit`, `Pillage`, `This`, `next`, `As`,
movement/status/combat-XP labels, and training `as`). The persistent KnownTexts
refresh imported 19,407 source occurrences; the current Composite authority is
11,945 entry points, 15 rules, and 308 runtime-map bindings. The patch was
rebuilt and the installed files were refreshed for manual testing; no game was
started.

The 2026-08-06 Leader-trait repair adds a narrow final-display fallback for a
RichTextLabel token boundary, not another source-string rewrite: exact runtime
plain forms `Leader Trait` and `Leader 特质` use `runtime-display-plain`, and
the two complete Leader-trait templates use `runtime-display-template` through
the bounded CJK word-bridge template path. Route future work on this display
form to `leader-trait-weight-tooltip-audit.md` and
`runtime-entrypoint-audit.md`; do not introduce a global `Leader` or `Trait`
translation.
