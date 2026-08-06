# Cold-Sensitive Trait Audit

## 2026-08-05 smoke-only repair

The reported clan-card trait tooltip comes from the `DESIRE_Warmth`
`descriptionForTrait` value in the installed, unmodified
`Content/Config/Primary/ClanDesires.xml`:

```text
unable to spend the winter inside the [SETTLEMENT] or as the [Resident|RESIDENT] of a [Structure|STRUCTURE]
```

The runtime redirect already passes
`AtTheGatesCommon.ns_Config.ClanDesireConfig::get_DescriptionForTrait()` through
the final rich-text localizer. Its reusable composition rule is
`runtime-display-richtext-fragment` at
`runtime-map:RichTextFragments`. The repair therefore replaces that complete
markup-bearing source template with
`无法在[SETTLEMENT]内过冬，或作为[Resident|RESIDENT]居住在[Structure|STRUCTURE]中`.
All three original keys and their order are preserved.

The previously registered `unable以 spend the winter inside the` exact and
plain-fragment variants did not match the source or the reported display, so
they were removed rather than retained as dead fallback rules.

`Build-Patch.ps1` completed successfully. Its generated runtime map contains
18 rich-text fragments and retains `DynamicCjk` with 149 runtime redirects.
The initial runtime-text regression failed only because its expected value
assumed the localizer itself renders the bare `[SETTLEMENT]` tag. That tag is
intentionally kept raw by the localizer and rendered by the game's later text
formatter; the linked `RESIDENT` and `STRUCTURE` displays were localized as
expected. The regression expectation will be corrected before the retry.

After correcting that assertion, `AtG.RuntimeText.Tests` passed. It verifies
the generated runtime map converts the complete source template while retaining
the raw settlement token for the game's formatter and preserving the localized
resident and structure concept links.

The first `Test-CompositeTextCatalog.ps1` run after regeneration correctly
reported stale SQLite runtime-map occurrences: the Composite authority had
12,043 entries and 389 runtime-map definitions, but the replacement source
definition had not yet been imported into `.cache/atg-catalog.sqlite`. Refresh
the source catalog before retrying this check; no additional translation change
is indicated.

`Export-KnownTextReview.ps1` then imported 19,505 source occurrences into
10,241 semantic groups and refreshed the exact runtime-map bindings. The
Composite validation can now be retried against the current authority.

The retry passed: `Test-CompositeTextCatalog.ps1` validated 12,043 entries,
15 rules, and the complete runtime-map binding set.

The manifest-backed installation refreshed successfully. The default main-menu
smoke reached a stable window in 8.25 seconds, completed eight stable checks
over 4.15 seconds, and reported no crash log, crash dialog, settings error, or
Windows error. The captured main menu was visually checked. The installed
`Content/Text/AtG.RuntimeText.tsv` SHA-256 matches the new patch artifact.

Per the smoke-only request, no save, clan card, trait hover, or other
black-box interface was opened. The target tooltip is covered by its exact
runtime-map regression and installed build, but not by a target-UI replay.
