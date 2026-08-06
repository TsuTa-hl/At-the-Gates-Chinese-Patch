# Obsessed-idea Tooltip Audit

## 2026-08-06 authoritative config-source correction

The later screenshot still displayed the exact underlined English phrase. That
observation disproved the prior assumption that its only relevant ingress was
the tokenized rich-label/runtime-map path. The exact source was found in
`Content/Config/Misc/Intensities.xml`, in the `INTENSITY_OBSESSED` node:

```xml
<description>[COLOR:BAD-RED]become obsessed[/COLOR] with the idea of</description>
```

The colour tag splits the otherwise continuous phrase, so the former full-text
runtime-map operands cannot match this config value. The stable direct display
lineage is `AtTheGatesCommon.ns_Config.GAME.BuildDescription_Desire`
(`0x06001732`), which substitutes the resolved intensity description into the
desire clause. The generated config patch now owns the exact node and writes
`<name>痴迷</name>` plus
`[COLOR:BAD-RED]会痴迷[/COLOR]于`, preserving the rich-text boundary.

`translations/config-node-misc-strings.json` is the source map. Its refreshed
Composite record is
`xml:source/Content/Config/Misc/Intensities.original.xml:c606cffb9531ea63`,
with `RuleId` `xml-existing-translation` and `RichTextMarkup` structure. The
uninterrupted runtime-map rows are retained only as narrow fallbacks for any
separate display path; the config-node mapping is authoritative for this
reported source string.

The focused `Obsessed intensity tooltip config preserves its rich-text
boundary` regression verifies the original node, ID, translated name, exact
tag-preserving result, and absence of ASCII prose outside the tags. Both patch
and runtime-text test projects, build, rich-text/concept-link/composite/catalog
gates, and installed config hash comparison passed. The refreshed installation
contains 58 manifest files and its `Content/Config/Misc/Intensities.xml`
SHA-256 matches the built patch.

The only runtime check was the required default main-menu smoke: the window was
ready in 8.21 seconds and stable for eight checks over 4.13 seconds; it showed
no crash-log update, crash dialog, settings error, or Windows error. No save,
new game, clan interface, or target tooltip was opened, so the target UI has
not been black-box replayed. The main-menu capture was visually checked before
cleanup and showed the Chinese menu labels.

## 2026-08-05 correction: tokenized rich-label ingress

The user's later screenshot still showed the exact underlined phrase
`become obsessed with the idea of`. That result falsifies the earlier
map-only conclusion: the exact runtime map rows were present, but one display
path never presented the complete phrase to the localizer.

The final static ingress inventory is now:

1. `TextFormatter::Process` (`0x06000198`), which filters complete raw text.
2. `CompositeString::Append_RawTextToFormat(StringBuilder, ...)`
   (`0x0600025D`), which filters complete rich text.
3. `CompositeString::Append_RawTextToFormat(string, ...)` (`0x0600025E`),
   which filters complete rich text.
4. `ClanDesireConfig::get_DescriptionForTrait` (`0x06000FEF`), which filters
   its complete rich-text return value.
5. `ClanDesireConfig::get_DescriptionForTrait2` (`0x06000FF1`), which filters
   its complete rich-text return value.
6. `ElfTools.Interfaces.Controls.RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Line`
   (`0x06000A0F`), which passes the label's already-tokenized words through
   `CjkWordWrapBridge::ProcessWord`.

The first five paths can match the existing full-text entries. The sixth splits
the reported text into `become`, `obsessed`, `with`, `the`, `idea`, and `of`,
so a whole-phrase mapping cannot match it. Direct game rendering remains
covered by the generated renderer redirects; static inspection found no source
`SpriteFont::MeasureString` or `SpriteBatch::DrawString` sink outside that
coverage.

`DisplayStringLocalizer` now derives a first-word sequence index from the
existing `RichTextFragments` map and accepts only configured, markup-free,
three-or-more-word exact sequences. The word bridge previews the real
`StringSplitter` state without mutating it, substitutes the configured value
`会痴迷于`, and consumes exactly the remaining five source words. This unifies
every discovered display entrance with the same existing translation while
avoiding a global replacement of words such as `become` or `obsessed`.

The new `AtG.RuntimeText.Tests` regression feeds the exact six-token stream
and asserts that it emits `会痴迷于` and resumes at the following word. A
nearby non-configured phrase (`become interested in something`) takes the
unchanged original path. Both runtime-text and patch test projects passed.
`Build-Patch.ps1` completed with `DynamicCjk`, 149 runtime redirects, five
full-value localization redirects, and the existing `P`/`F`/`R` map variants
all resolving this phrase to `会痴迷于`. Tag, rich-text, concept-link, font,
build-report, IL-risk, Composite, KnownText, and TODO static gates also passed.

The refreshed installation's `AtG.RuntimeText.dll` SHA-256 equals the patch
artifact (`099731BE85E3EEC933F1BD387CB7AF80A924E30D218CD537C2276D0F21EC4530`).
The requested default main-menu smoke passed: window ready in 8.29 seconds,
then eight stable checks over 4.19 seconds, with no new-game attempt, crash
log, crash dialog, settings error, or Windows error. The smoke capture itself
contained the foreground Chrome window rather than the game, so it is not
usable visual evidence. No save, new game, clan card, or target tooltip was
opened; the target UI remains deliberately un-replayed under the smoke-only
scope.

## 2026-08-05 smoke-only verification repair

The screenshot's underlined `become obsessed with the idea of` label is the
display text of the clan-desire tooltip's rich concept-link form. The installed
runtime map already contains the exact no-space and trailing-space variants in
`PlainText`, `PlainTextFragments`, and `RichTextFragments`, all translating to
`会痴迷于`. The corresponding Composite entry points reuse
`runtime-display-plain`, `runtime-display-fragment`, and
`runtime-display-richtext-fragment` respectively.

The active Common patch also returns both
`ClanDesireConfig.get_DescriptionForTrait` (`0x06000FEF`) and
`get_DescriptionForTrait2` (`0x06000FF1`) through
`DisplayStringLocalizer.LocalizeRichText`. The built and installed
`AtTheGatesCommon.dll`, `AtG.RuntimeText.dll`, and `AtG.RuntimeText.tsv` were
hash-equal at this check.

The missing regression boundary was the actual concept-link spelling:
`[become obsessed with the idea of|DESIRE]`. The generated runtime-map test now
asserts that it becomes `[会痴迷于|DESIRE]`, preserving the opaque concept key.
`AtG.RuntimeText.Tests` passed after this addition. This task remains
smoke-only: build, refresh the installation, and run only the default
main-menu smoke; do not replay the clan-tooltip UI as a black-box scenario.

`Build-Patch.ps1` then completed successfully with `DynamicCjk`, 149 runtime
redirects, 46 plain-text entries, and 294 plain-text fragments. The existing
Common return filters remained in the built patch; no broad concept-ID or
word-level rewrite was introduced.

The manifest-backed installation refreshed successfully. The default
main-menu smoke passed: window ready in 11.88 seconds, eight stable checks over
4.15 seconds, no new-game attempt, and no crash log, crash dialog, settings
error, or Windows error. The main-menu screenshot was visually checked and
shows Chinese menu labels. No clan card, trait hover, save load, or other
black-box interface was opened by request; the exact tooltip conversion is
therefore verified by the generated-map regression and installed-artifact
hashes rather than a target-UI replay.

Post-install SHA-256 comparisons confirmed that `AtTheGatesCommon.dll`,
`AtG.RuntimeText.dll`, and `Content\\Text\\AtG.RuntimeText.tsv` each match the
newly built patch artifact.
