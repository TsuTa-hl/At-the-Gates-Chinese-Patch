# Translation Style

Use this guide when translating newly discovered safe text or reviewing existing
Chinese strings.

## Setting

- The game is a 4X strategy game about late antiquity, the Roman frontier,
  migrating peoples, tribal survival, and so-called barbarian factions.
- In Chinese terms, treat it as a `古罗马晚期` / `蛮族部族` historical strategy
  setting about migration, survival, and frontier politics.
- Chinese text should fit a historical strategy UI, not a modern casual app.

## Voice

- Prefer concise, steady, historically grounded Chinese.
- Avoid internet slang, modern jokes, over-literal machine translation, and
  excessive literary/classical wording.
- Use direct strategy-game language for commands, costs, requirements, and
  warnings.
- Keep character dialogue natural and readable, with light period flavor only
  when the English supports it.

## UI and Layout

- Button labels should be short and action-oriented.
- Tooltips may use fuller sentences, but should stay compact enough to fit the
  panel.
- Do not add artificial spaces between Chinese characters.
- Preserve readable spacing around icons, numbers, variables, and inline tags.
- If a long English sentence must fit a narrow UI surface, compress the Chinese
  while preserving gameplay meaning.
- Rich-text concept links may render with extra visual spacing around the
  linked Chinese term. Do not add padding characters to compensate, and do not
  remove useful concept tags solely for cosmetic spacing unless the specific UI
  has been proven safe without the tag.

## Distinct Diplomacy Actions

- Translate `Declare War` as `宣战`: this is the player's direct declaration.
- Translate `Make War` as `挑起战争`: this orders a selected leader to declare
  war on another faction.
- Do not merge those labels: their targets and effects are different even when
  they appear together in the diplomacy screen.

## Roman Faction Variants

- Translate the Eastern and Western Roman faction display families consistently
  as `东罗马` and `西罗马`.
- Apply the same distinction to full empire names, `Independents`, `Rebels`,
  and the `(I)` / `(R)` abbreviations. These are runtime display labels; do not
  alter the underlying faction IDs.

## Tags and Placeholders

Preserve these exactly unless the surrounding system explicitly requires a
translated display term:

- `[TAG]`, `[Tag|KEY]`, `[HOTKEY:*]`, `[COLOR:*]`, `[NEWLINE]`,
  `[BLANK-LINE]`
- Runtime variables, IDs, enum-like keys, file paths, URLs, version numbers,
  World IDs, and generated names
- Punctuation required by the token or tag format

For composed or rich-text templates,
`translations/composite-text-rules.json` owns argument ordering, structural
preservation, and reusable rule selection. Query it directly by `EntryPointId`
and `RuleId`; user review output is not AI input. Prefer the complete display
template when it controls word order, argument binding, or rich-text structure.
Otherwise, a verified exact replacement of a complete formatted segment may be
reused globally.

## Concept Links

- Treat `[display text|CONCEPT-KEY]` as an interactive concept link. Preserve
  the key exactly and change only the display text when a display-only edit is
  safe.
- Before changing a concept-link label, query
  `translations/concept-key-translations.json` by `Key`. It records each
  source label with its observed Chinese label(s) from static inputs.
- Prefer a keyed global replacement of the complete formatted link when the
  same source label and `CONCEPT-KEY` have one unambiguous Chinese label, every
  verified occurrence is display-only, and the tag structure is unchanged.
  This is the normal way to reuse translations of common terms, short phrases,
  and labels.
- Do not globally replace a bare display word without its `CONCEPT-KEY`, or a
  key/label pair with multiple observed Chinese labels. In those cases, choose
  the full template or a scoped entry point after checking the affected
  occurrences.
- Rebuild and validate the concept-key map after changing either static input.
- A concept tooltip registration is a separate, complete display boundary from
  its `[label|KEY]` link. Before editing a tooltip description, query the
  `concept-tooltip-static-registration` rule and the 111-entry
  `ConceptTooltipCatalog`; do not assume the 109-key link-label map is a
  complete tooltip inventory.
- Keep tooltip concepts distinguishable when they can appear together. Reuse
  the approved keyed label for a concept, but do not collapse different keys
  into the same Chinese term merely because their English labels are similar.

## Numbers and Values

- Preserve the sign, comparison, operation, unit, and arithmetic meaning of a
  numeric value. Keep percentages and multipliers distinct unless the complete
  source template proves a conversion.
- Use Arabic digits for values, percentages, and multipliers unless a displayed
  term itself requires another form. Keep the number and its unit together and
  avoid artificial Chinese spacing.
- For dynamic values, use a reusable complete template or scoped rule whenever
  argument order, unit placement, or grammatical role changes. Do not apply a
  global fragment replacement that can alter the numeric operation or sentence
  relation.

## Dynamic Requirement Messages

- For resource-shortage requirements, preserve the resource and amount
  placeholders and use `缺少足够的{资源}（还差{数量}）。`.
- The final UI may rephrase the underlying condition (for example, `lacking
  sufficient ...`). Bind the complete final template in
  `runtime-display-strings.json`; do not translate loose word fragments.

## Acceptable Remaining English

The following may remain English unless a safe display-only source is identified:

- Generated character or clan names
- Generated notification prefixes such as `Clan <Name>` until a safe
  display-only source is isolated
- World IDs
- Version numbers
- URLs and file paths
- Hotkey labels and technical markers
- The product title `At the Gates` when it appears as a title/name rather than
  ordinary prose
- Non-tribal faction names and labels whose logic-sensitive source has not been
  separately mapped

Do not force these into Chinese solely for stylistic consistency.
