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
  under `.tmp/review-views`: `KnownTexts` reads SQLite, `Composite` reads
  `translations/composite-text-rules.json`, and `Todo` joins those two source
  stores directly. `Todo` never reads a generated KnownTexts or Composite
  view. The views do not replace SQLite for exact matching.

The `Composite` CSV uses `RowKind=Entry` for entry points and `RowKind=Rule`
for every reusable rule, including a rule that is not currently bound to an
entry point. This preserves the rule summary without an auxiliary Markdown
index.

Static CSV coverage is owned by `Test-KnownTextReviewExport.ps1`,
`Test-CompositeTextCatalog.ps1`, and `Test-LocalizationTodoList.ps1`. They
verify source-only inputs and file shape; they do not launch the game or replace
a UI smoke test for a localization change.

Lack of a screenshot is not a reason to skip an already discovered
player-visible candidate. Record the source classification and choose the
appropriate smoke or UI evidence instead.

After changing source catalog data or composition rules, generate and check
the complete temporary CSV worklist:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\review\Generate-ReviewViews.ps1 -View Todo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-LocalizationTodoList.ps1
```
