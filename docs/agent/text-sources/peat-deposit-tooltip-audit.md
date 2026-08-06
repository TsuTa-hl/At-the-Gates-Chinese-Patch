# Peat Deposit Tooltip Audit

## 2026-08-06: all deposit-size descriptions

The visible residual comes from three XML descriptions in
`source/Content/Config/OnMap/Deposits.original.xml`, not from the localized
`TEXT.Name.Deposit.*PeatDeposit` name keys. All three descriptions use the
same display fragment `Peat [Deposits|DEPOSIT]` and a second sentence beginning
`Peat can only be found in`:

| Config ID | Size variant |
| --- | --- |
| `DEPOSIT_PEAT` | normal |
| `DEPOSIT_PEAT_LARGE` | large |
| `DEPOSIT_PEAT_VAST` | vast |

`translations/config-node-onmap-strings.json` now supplies exact Chinese XML
descriptions for all three. The replacement uses `泥炭[矿床|DEPOSIT]` so the
heading and linked display are both Chinese, and preserves every machine key,
plural selector, and `[BLANK-LINE]`. The reused composite rule is
`xml-existing-translation` (`EntryPointId` prefix `patch:xml`).

## Static-test handoff

Build completed and wrote all three matching nodes to
`patch/Content/Config/OnMap/Deposits.xml`. The direct node equality check
passed for all three localized descriptions. An initial residual scan was
discarded because it incorrectly treated the required `[PEAT-MINE-1]` concept
key as display text; the follow-up scan excludes bracketed machine keys.

That follow-up scan passed for all three entries, as did rich-text tag
preservation. The remaining static scripts are launched as isolated child
processes because the rich-text script intentionally terminates its invoking
PowerShell session after success.

All remaining gates then passed: concept-link targets, generated aliases,
font budget, runtime build report, IL rewrite risk validation,
composite-text catalog, known-text review export, and localization todo export.
The latter reported no unreviewed composite entries.

Validation remains smoke-only: no save, new game, or peat-tooltip interaction
is performed.

## Install and smoke conclusion

The refreshed patch was installed through the existing manifest workflow. The
installed `Content/Config/OnMap/Deposits.xml` and
`Content/Text/AtG.RuntimeText.tsv` SHA-256 hashes matched the patch outputs.
Default main-menu smoke completed with a ready, stable window (8 stable checks
over 4.14 seconds), no crash-log update, and no crash, settings, or Windows
error dialog. `IncludeNewGame` and `NewGameAttempted` were both `False`; no
black-box peat-tooltip interaction was performed.
