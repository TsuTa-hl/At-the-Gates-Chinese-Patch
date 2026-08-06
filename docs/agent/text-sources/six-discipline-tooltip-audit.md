# Six Discipline Tooltip Audit

## 2026-08-06: clan-training discipline descriptions

The six hover descriptions are XML config text, loaded by
`AtTheGatesCommon.ns_Config.DisciplineConfig::Load` from
`Content/Config/Misc/Disciplines.xml`; they are not a Common/UI `ldstr` or a
single runtime-display fragment. The original snapshot is retained at
`source/Content/Config/Misc/Disciplines.original.xml`, matching the installed
game content apart from normalized line endings. The SQLite catalog and
`docs/review/generated/static-text-candidates.csv` both identify the six
`description` operands by stable config ID.

| Config ID | Composite EntryPointId |
| --- | --- |
| `DISCIPLINE_HONOR` | `xml:source/Content/Config/Misc/Disciplines.original.xml:896db2a4e3cc5f7e` |
| `DISCIPLINE_AGRICULTURE` | `xml:source/Content/Config/Misc/Disciplines.original.xml:1412ad2db12fcfb2` |
| `DISCIPLINE_LIVESTOCK` | `xml:source/Content/Config/Misc/Disciplines.original.xml:f58091261e7dd567` |
| `DISCIPLINE_METALWORKING` | `xml:source/Content/Config/Misc/Disciplines.original.xml:5cc0cdc34a50c711` |
| `DISCIPLINE_CRAFTING` | `xml:source/Content/Config/Misc/Disciplines.original.xml:f6f7c8a41b1ddd15` |
| `DISCIPLINE_DISCOVERY` | `xml:source/Content/Config/Misc/Disciplines.original.xml:c9ee1770edec8008` |

`translations/config-node-misc-strings.json` now supplies the six exact
description replacements through the existing `xml-existing-translation`
rule. Each starts with the same localized explanatory format:
`是六种[纪律|DISCIPLINE]之一，[职业|PROFESSION]和[氏族|CLAN]都可归属其中。[BLANK-LINE]`.
The discipline-specific second paragraphs remain distinct so the original
information about plants, animals, metallurgy, crafting, discovery, and honor
professions is not flattened. Every original machine key, plural/raw token,
and `[BLANK-LINE]` remains intact; only display text and prose are localized.

## Static-test handoff

`Build-ConfigNodePatch.ps1` wrote all six descriptions to
`patch/Content/Config/Misc/Disciplines.xml`; a direct XML equality check
confirmed every generated description equals its configured translation.
The added `AtG.Patch.Tests` regression requires exactly these six IDs, the
shared prefix, absence of English prose outside tags, and preservation of all
source tag keys/tokens.

`Build-Patch.ps1` completed in 6.8 seconds. `AtG.Patch.Tests` and
`AtG.RuntimeText.Tests` passed, followed by rich-text tag preservation,
concept-link targets, aliases, font budget, build report, IL-risk,
Composite, KnownTexts, and TODO gates. The regenerated Composite catalog
reports the six recorded EntryPointIds as `ExistingRule`, `Localized`, and
`xml-existing-translation`.

## Install and smoke conclusion

The manifest-backed installer refreshed the existing patch successfully. The
installed `Content/Config/Misc/Disciplines.xml`,
`Content/Text/AtG.RuntimeText.tsv`, and `AtG.RuntimeText.dll` SHA-256 hashes
all match the generated patch; the refreshed manifest contains 57 files.

The default main-menu smoke completed in 16.6 seconds: the window was ready
after 8.21 seconds and stable for eight checks over 4.13 seconds. The screenshot
shows the localized main menu. `CrashLogUpdated`, `CrashDialogSeen`,
`SettingsErrorSeen`, and `WindowsErrorSeen` were all `False`.
`IncludeNewGame=False` and `NewGameAttempted=False`. Per request, no save,
new game, clan-training screen, or discipline-tooltip interaction was
performed; visual verification of the six target hover descriptions remains
intentionally outside this smoke-only session.

## Final hygiene

The generated and installed discipline XML files were re-parsed as UTF-8 and
both contain the six expected discipline nodes. Task-scoped temporary review
views, catalog exports, and the smoke screenshot were removed after their
results were recorded; the end-of-task cleanup reported zero remaining
candidates.
