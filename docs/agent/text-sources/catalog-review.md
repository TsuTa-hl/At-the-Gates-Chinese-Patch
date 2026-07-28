# Catalog and Review Exports

The SQLite catalog is the source of truth for every discovered text occurrence.
Use it before searching source files from a screenshot symptom.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search -CatalogText '<visible text>' -CatalogLimit 20
```

Add `-CatalogSource '<source fragment>'` when the likely file or assembly is
known. For a DLL match, take exact operands from the generated `ldstr` catalog,
not from a whitespace-normalized review export.

- `.cache/atg-catalog.sqlite`: occurrence, group, binding, and evidence store;
  it is generated/local state and not hand-edited.
- `docs/review/generated/`: exact source catalogs used for refresh and patch
  operands; they are not human review views.
- `docs/review/Generate-ReviewViews.ps1`: makes three disposable CSV views
  under `.tmp/review-views`: all three read the SQLite occurrence catalog and
  `translations/composite-text-rules.json` directly. The source JSON persists a
  stable `KnownTextReference` for every literal that has a source KnownText
  occurrence (managed `MethodToken + ILOffset`, full XML XPath, English text
  key, config `ID + relative XPath + Index`, or a runtime-display map
  `RuntimeMapSection + RuntimeMapOriginal + optional RuntimeMapConceptKey`).
  Runtime-display entries are source occurrences in
  `translations/runtime-display-strings.json`, explicitly distinguished from a
  raw DLL/XML occurrence. At view generation, a locator is resolved to the
  local occurrence and semantic-group IDs only when the source locator and
  original text/key agree. `KnownTexts` and `Composite` expose both sides of
  the link; `Todo` uses the same exact links. No view reads another view, and
  the views do not replace SQLite for exact matching.

  An unresolved locator is retained as explicit evidence in
  `KnownTextUnresolvedReferencesJson`; it is not replaced with a same-method,
  same-text, or other heuristic association. If the catalog is rebuilt, rerun
  the CSV generator to resolve the stable locators against its new local IDs.

The `Composite` CSV uses `RowKind=Entry` for entry points and `RowKind=Rule`
for every reusable rule, including a rule that is not currently bound to an
entry point. This preserves the rule summary without an auxiliary Markdown
index.

Static CSV coverage is owned by `Test-KnownTextReviewExport.ps1`,
`Test-CompositeTextCatalog.ps1`, and `Test-LocalizationTodoList.ps1`. They
verify source-only inputs and file shape; they do not launch the game or replace
a UI smoke test for a localization change.

## Composite-to-KnownText static verification

The durable relationship is validated statically with the three CSV tests above:
the Apiary config description proves the `ID + XPath + Index` path, and
`TEXT.Credits.Conifer` proves the English text-key path. The tests also reject
the retired method-level association and require each linked CSV row to carry
the occurrence/entry-point evidence. This metadata-only work has no gameplay,
package, or UI-smoke session; generated CSVs remain disposable under `.tmp`.

Latest source-only validation (2026-07-25) resolved 8,375 of 9,239 persisted
Composite literal locators against 18,851 current catalog occurrences, yielding
12,437 exact link records across 11,417 Composite entries. Before the runtime
map entries were imported, an exact static search of the prior 18,802-occurrence
catalog found no raw DLL/XML/English occurrence for any of the 31 bindings.
They are therefore recorded as the 31 canonical runtime-display-map KnownText
occurrences, each with an exact reverse Composite link; the remaining 864
locators are exported as unresolved evidence, not inferred links. That run
passed `Test-CompositeTextCatalog.ps1`, `Test-KnownTextReviewExport.ps1`,
`Test-LocalizationTodoList.ps1`, `AtG.Patch.Tests`, `AtG.Catalog.Tests`, and
`Test-DocumentationRouting.ps1`. No game process was started.

Latest Composite localization audit (2026-07-25) adds 251 exact
`runtime-display-template` entry rules for every discovered managed composition
with readable multi-word English. It deliberately does not use legacy
`Safety`/`ReasonCode` classifications: remaining single-token paths, control
names, input keys, serialization/config keys, and date/format markers are
classified from their exact operands as structural, while three entries remain
`RejectedBySmoke` from `trial-localization-state.json` (including the
whitespace-normalized historical `No` locator). The audit has zero
`ReviewedNoSafeRule` entries. A runtime-map build caught one repeated source
template with divergent Chinese text; both callers now use the same template.
`Test-CompositeTextCatalog.ps1`, `Test-KnownTextReviewExport.ps1`,
`Test-LocalizationTodoList.ps1`, `AtG.Patch.Tests`, and
`Test-DocumentationRouting.ps1` passed after the correction. This was a
source-only session; no game process was started.

The expanded Managed-and-XML audit (2026-07-25) treats XML `TEXT.*` values as
runtime text-key references rather than as visible key names. It verified 1,972
references against a changed localized `English.xml` target and 35
numeric/placeholder-only targets as language-neutral. The 28 referenced keys
absent from the base English XML are now explicit `runtime-text-key-additions`
KnownTexts and patch entries. The remaining visible Tech composites use four
count-checked config fragment replacements (448 shared ` Upgrade` suffixes,
two standalone `Upgrade` links, and two learned-tech phrases); all preserve
their source markup and concept keys. The catalog now has 4,957 localized
Managed/XML Composite entries and two recorded smoke rollbacks, with no
unreviewed audited Composite. The refreshed 18,879-occurrence catalog resolves
8,403 of 9,239 stable literal locators and records 12,465 exact reverse links.
`Test-KnownTextReviewExport.ps1`, `Test-CompositeTextCatalog.ps1`, and
`Test-LocalizationTodoList.ps1` passed; the temporary CSVs remain disposable.

The 2026-07-26 diplomacy repair keeps exact operand ownership separate from
final-display handling. `Screen_Diplomacy.CreateControls_Fixed` owns the five
static labels (`Friends`, `Enemies`, `Approach`, `Influence`, and `Leverage`)
and therefore uses five exact UI IL rewrites. `Minor Leader` has no raw catalog
literal, so its exact final display value is owned by the `PlainText` mapping
in `translations/runtime-display-strings.json`. The only reviewed source
fragment `in ` is `ATGCity.BuildTrainingProjectDescription`
`0x0600086c:IL_00ac`; its exact Game rewrite emits empty text because the
preceding localized operand already supplies `于`. Short determiner and
preposition fragments are not global runtime-display operands: this prevents a
source-specific `The ` rewrite from changing unrelated proper names.

The first source-only KnownTexts export after adding `Minor Leader` correctly
detected that the durable Composite index still described the previous 31
runtime-display-map bindings. The source-driven catalog regeneration now has
32 such bindings. The CSV tests now derive that count from the source map;
their exact reverse-link requirement remains unchanged. A Composite CSV retry
then correctly exposed the remaining stale source input: the replaceable SQLite
occurrence catalog still predated the new mapping. Rebuild that catalog through
`Export-KnownTextReview.ps1` before retrying; do not manufacture a link in a
generated CSV view.

The rebuilt source catalog and regenerated Composite authority now validate
cleanly: `Test-CompositeTextCatalog.ps1` resolves 8,410 of 9,246 literal
locators, `Test-KnownTextReviewExport.ps1` exports all 32 runtime-map bindings
with exact reverse links, and `Test-LocalizationTodoList.ps1` reports zero
unreviewed or reviewed-no-safe Composite entries. Their CSV outputs are
temporary `.tmp` views generated directly from SQLite and the rule/map source.

Lack of a screenshot is not a reason to skip an already discovered
player-visible candidate. Record the source classification and choose the
appropriate smoke or UI evidence instead.

After changing source catalog data or composition rules, generate and check
the complete temporary CSV worklist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\review\Generate-ReviewViews.ps1 -View Todo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-LocalizationTodoList.ps1
```
