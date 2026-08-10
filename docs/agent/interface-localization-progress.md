# Interface Localization Progress Audit

This is a static source-and-entry audit, not UI coverage. Generate a fresh
isolated report with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-InterfaceLocalizationProgress.ps1
```

The exporter writes disposable summary/items/metadata files under `.tmp`. It
rebuilds the KnownText data unless an explicitly supplied private snapshot is
requested.

`VisibleLocalizationRate` counts visible translatable source items with a
non-empty Chinese translation and an exact locator. `AllKnownTrackingRate`
counts every known item with an explicit route; technical, structural,
rejected, language-neutral, and unclassified items remain separately visible.

`BuildArtifactState=Current` only when the generated build report's input digest
matches the current source maps. Missing or legacy reports are never treated as
current output.

Use the current generated metadata as the baseline. Do not copy dated totals or
static-only results into this document; record actual smoke or black-box status
in the owning scenario and current-status records.
