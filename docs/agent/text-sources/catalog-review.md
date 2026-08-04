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

The 2026-08-01 ERJ-UUX repair added the 57 neutral tribe names plus their
split tooltip fallbacks and the relation-level fragments to the runtime map.
The regenerated catalog contains 273 runtime-map definitions and the exact
Composite index links every one to a runtime-display KnownText occurrence.

The 2026-08-01 ERJ-UUX diplomacy-value repair was static-only (the game was
not started). Catalog queries distinguished the numeric-value surfaces from
the Relationship Level and Influence concept surfaces: `Default is `, `from `,
and `differing religious beliefs.` are now split runtime fragments, while the
existing full tooltip rules remain separate. The standalone `The` display
fragment is now empty, and the two family/property settlement IL operands
that prepend `The ` also remove only that article; full tribe-name operands
remain intact. `Factions.original.xml` contains 57 neutral duplicate names;
all 57 have translated config nodes and both full (`The X`) and bare (`X`)
runtime fallbacks; the neutral city label `Minor Tribe` is translated in both
the config node and the runtime map. Static build, catalog, KnownTexts, TODO, rich-text,
concept-link, IL-risk, routing, scenario-schema, and runtime unit tests passed.

The 2026-08-01 CLD-DML horse-herd and clan-tooltip repair first reproduced both
reported residuals on the fixed save: the horse description was split into
runtime draw nodes (`added`, `your`, `Stockpile`, `Constructing`, `a`), and the
clan-card countdown contained a standalone ` in ` node. The horse map now has
three exact templates with the original concept-link order preserved
(`STOCKPILE` before `CONSTRUCT` and `PASTURE`); the clan countdown uses a
scoped `BuildBasicDescription` (`0x0600171f`, IL offset 693) rewrite to
`，还需`, leaving unrelated `in` occurrences untouched. The existing scoped
production and battlefield rules remain unchanged.

Superseded by the 2026-08-02 manual visual result: the exact whole-template
and plain `added to your Stockpile` rules did not reach the split horse display.
Use the smaller `runtime-richtext-final-process` suffix rules, preserving the
original link-key order (`STOCKPILE`, `CONSTRUCT`, `PASTURE`), and remove the
broad ` to` fragment because it produced `added以`. The displayed clan-card
countdown is emitted by `ClanTooltip.BuildTooltip` (`0x060002f0`, IL offsets
2299 and 2405), not by either description-builder operand documented above;
those two exact tooltip operands now use `，还需`. This is static-source repair
evidence only and awaits the user's visual verification.

The regenerated Composite authority has 11,691 entries, 15 rules, and 284
runtime-map definitions; the source KnownTexts export contains 19,152
occurrences and 12,772 Composite references. Build and install completed, and
static Composite, KnownTexts, TODO, rich-text, concept-link, IL-risk,
scenario-schema, runtime-build-report, and runtime unit tests passed. A
post-install black-box replay was not run: automatic black-box testing was
disabled by the user immediately after installation, so no visual pass is
claimed for CLD-DML in this session.

On 2026-08-02 the follow-up static session regenerated the Composite and
KnownTexts indexes (11,696 Composite entries; 19,157 KnownText rows), passed
rich-text, concept-link, composite, KnownTexts, TODO, IL-risk, runtime-unit,
runtime-build-report, documentation-routing, and scenario-schema checks, then
rebuilt and refreshed the manifest-backed installation. The installed Common
DLL and runtime display map hashes match the patch output; the map contains the
two horse suffix rules and the Common rewrite contains the shared Chinese
countdown literal used by the two `ClanTooltip` operands. `Test-GameLaunch.ps1`
was intentionally not run under the no-automatic-black-box policy, so this is
a static smoke rather than a UI verification.

The 2026-08-02 CLD-DML correction supersedes the preceding horse-template
note. The user correctly identified that `未识别植物 in 4 回合` remained: the
installed Common catalog shows that this card detail is emitted by
`ProfessionTooltip.BuildTooltip` (`0x06000348`, IL offsets 6205 and 6306),
not the already-localized `ClanTooltip` operands. Both exact, method-scoped
operands now translate ` in ` to `，还需`.

The actual horse text is the six stable `deposit/description` nodes in
`Content/Config/OnMap/Deposits.xml` (`DEPOSIT_HORSES`, its large and vast
variants, plus the three `DEPOSIT_PUREBREDS` variants). It does not match the
previous runtime template: its real path uses `[HORSE-PASTURE-1]` and the
`added to your ... and then used` grammar. The raw source snapshot is retained
only for these ID-scoped config-node operands; the six full descriptions now
patch that XML directly, preserving every rich-text tag. The obsolete horse
runtime exact, fragment, and test-template rules were removed rather than
layered on top of the true source.

The static source catalog records the complete deposit inventory separately
from the six active patch entries. A config XML entry becomes an audited
Composite entry point only when it binds to a translation rule, so the
remaining unlisted deposit descriptions stay explicitly reviewable instead of
being misreported as translated by this narrow repair. After build,
`xml-existing-translation` binds all six horse EntryPointIds. Rich-text,
concept-link, Composite, IL-risk, runtime-unit, build-report, font, and
installed-file hash checks passed. The refreshed installed DLL and Deposits.xml
match the patch output. No game process or black-box test was started; visual
verification remains with the user.

The final static build for this correction completed in 13,596 ms. The regenerated
Composite index contains 11,844 entry points and the KnownTexts export contains
19,305 rows. Documentation-routing and scenario-schema validation were rerun after
the record update and passed. No game process was started.

The 2026-08-02 MWC-LZR static repair added ID-scoped OnMap descriptions for the
base, large, and vast berry deposits, reusing the existing berry Composite
entry. The profession tooltip operands in `PropertyBlueprint.BuildDetailsString`
(`0x06000118`) and the two `HumanReadableMod` (`0x06000207`) `increased by`
operands now resolve to `提高`; the scoped `Supply Level` and `Traits`/`Crimes`
fragments remain linked Chinese concepts, and the production alternative
separator is `；或`. The Collier description key, Catapult `Supply` concept,
Instructor `Traits`/`Crimes` concepts, and Bow-Legged `of a` fragment are now
covered by their key-/runtime-scoped maps (the latter renders as `，驻留在`),
with no global fallback. Static source checks and the build passed. The user
requested no game or black-box test for this repair; MWC-LZR remains pending
manual verification after installation.

The 2026-08-02 RXL-CQW repair used the source catalogs and the existing
Composite authority before editing. `Structures.original.xml` contains ten
`fromDescription=Innate` nodes; the ID-scoped `CompositeReplacements` XPath
patches exactly those ten nodes to `先天`. The Common managed source
`GAME.BuildDescription_Abilities` (`0x06001724`, IL offset 1068) owns the
knowledge-profession countdown literal ` in `; its reused EntryPointId is
`managed-map:hardcoded-common-il-rewrite.json:0x06001724:IL_042C` with RuleId
`il-rewrite-common`, localized to `，还需`. The existing RXL-CQW bandit
operands retain their scoped EntryPointIds, including
`managed-map:hardcoded-common-il-rewrite.json:0x06000118:IL_1894` for `Innate`
and the UI `Low`/possessive fragments. Static Composite/KnownTexts/TODO,
rich-text, concept-link, IL-risk, and scenario-schema checks passed; the
installed fixed-save replay then passed all nine RXL-CQW resource, unit-stat,
and visible/scrolled profession points. No random-world data was used.

The 2026-08-02 numeric-modifier normalization keeps the existing
`HumanReadableMod` EntryPointIds and changes only their display wording:
`quadrupled`/`tripled`/`doubled` now use `变为4倍`/`变为3倍`/`变为2倍`, while the
fixed positive percentages use `提高75%`, `提高50%`, `提高33%`, `提高25%`, and
`提高20%`. The dynamic `>100` branch was source-checked: its argument is an
integer percentage, so the scoped `HumanReadableModDynamicPercent` operation
retains that integer and appends `%` (for example, 400 becomes `提高400%`).
The Composite catalog was regenerated from the managed map and no game or
black-box test was run; installation was refreshed for manual verification.

The 2026-08-02 SDN-UXO hive repair queried the source deposit catalog before
editing. `DEPOSIT_BEEHIVE`, `DEPOSIT_BEEHIVE_LARGE`, and
`DEPOSIT_BEEHIVE_VAST` now have ID-scoped full descriptions in
`config-node-onmap-strings.json`; all `[BLANK-LINE]`, concept links, and
harvest/produce operands are preserved, and the source `to` connector is no
longer exposed. The runtime display map now covers all 16 distinct large/vast
size suffixes found in `Deposits.original.xml` (deposit, field, grove, herd,
hive, patch, school, and meteorite variants), including both hive exclamations.
The generic field suffix is `田地` so wheat, barley, grapes, and flax share one
safe wording rather than inheriting a wheat-only label. Composite was rebuilt
to 11,875 entries and the KnownTexts export to 19,337 source occurrences;
static tag, concept-link, Composite, TODO, IL-risk, runtime-report, scenario,
and font checks passed. The installed `Deposits.xml`, runtime map, and managed
DLL hashes match the patch output. The SDN-UXO save was not present locally, so
only the default main-menu smoke was run; the target tooltip remains pending
manual replay on that save.

The 2026-08-03 UBL-TVF residual cleanup is static-only. The forage action's
`SelectionPanel.AddButton_Forage` operands at IL offsets 944 and 1013 now map
the residual ` will ` and `This ` connectors to `将` and `该`. The rich-text
fragment `become obsessed with the idea of` is registered as `会痴迷于` in the
runtime rich path, with the existing plain fallback retained. Composite and
KnownTexts were regenerated (11,914 entry points; 15 rules; 293 runtime-map
bindings), and the static tag, alias, font, hover-regression, TODO, and build
gates passed. The patch was built, uninstalled, and installed; the installed
runtime DLL and TSV hashes match `patch`. No game or black-box test was run;
manual visual verification remains with the user.

The 2026-08-03 priority continuation exposed a stale persistent catalog rather
than a missing source definition: the first Composite validation saw new
runtime-map locators absent from `.cache/atg-catalog.sqlite`. Re-running
`Export-KnownTextReview.ps1` from the source catalogs refreshed the database
(19,407 source occurrences), after which Composite validation passed with
11,945 entry points, 15 rules, and 308 runtime-map bindings. The final static
pass also validated tags, aliases, fonts, hover regressions, TODOs, runtime
build output, install/uninstall refresh, and scenario schema. No game was
launched; manual replay remains the next verification step.
