# Catalog Operations and User Review Exports

The SQLite catalog is the first lookup for screenshot-discovered English, raw
keys, mojibake, and tags. Query it through catalog tooling before any direct
source search. AI operands must use the exact `Original`, `SourceFile`, and
`Locators` fields returned by SQLite; AI never generates or reads user review
exports.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search -CatalogText '<visible text>' -CatalogLimit 20
```

Add `-CatalogSource '<assembly or path>'` when known. For DLL edits, use the
exact SQLite operands; never pass through a user review export.

Authorities:

- `.cache/atg-catalog.sqlite`: local occurrence, group, binding, exact-source,
  and locator database; it is the AI query and maintenance surface.
- `translations/composite-text-rules.json`: durable composed-display bindings.
- `docs/review/Generate-ReviewViews.ps1`: user-operated `KnownTexts`,
  `Composite`, and `Todo` exporter under `.tmp`; AI maintains this script but
  does not generate or read its views.

Every literal Composite reference carries exactly one durable source locator:
managed `MethodToken + ILOffset`, full XML XPath, English text key, config
`ID + XPath + Index`, or runtime-map section/original/key. An unresolved
locator remains explicit rather than being guessed from a similar method or
string.

After source-map or composition changes, refresh the SQLite catalog when its
source data changed and run the xUnit-owned static checks. User-generated
User review exports do not replace a real main-menu smoke for an installed
localization change.
