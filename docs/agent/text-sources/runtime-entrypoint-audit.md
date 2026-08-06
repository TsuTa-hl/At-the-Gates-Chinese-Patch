# Runtime Entry-point Audit

## 2026-08-06: safe tokenized-template support in RichTextLabel

`CjkWordWrapBridge` previously reconstructed only configured
`RichTextFragments`; it therefore skipped a configured runtime `Template`
when `RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Line`
(`0x06000A0F`) delivered the template as individual splitter words. This was
the remaining ingress for the Leader-trait label after the direct Common IL
rewrite and complete-value template had both passed their focused checks.

The bridge now also indexes opt-in runtime templates that are safe to match as
word sequences: exactly one argument, a literal prefix containing at least two
space-separated words, a nonempty literal suffix after the argument, no rich
text markup, and no more than eight words. It performs a bounded reconstruction
and reuses the normal exact template matcher; unmatched input uses the prior
word-processing behavior. The current map enables this only for the two
Leader-trait templates (`Leader Trait ({arg:0})` and
`Leader 特质（{arg:0}）`), so this is neither a global word replacement nor a
general arbitrary-template parser. See
`leader-trait-weight-tooltip-audit.md` for the concrete display operands,
Composite entry points, regression cases, and smoke-only limitation.

## 2026-08-05: tokenized RichTextLabel correction for the obsessive tooltip

The later obsessive-trait capture proved that the five `LocalizeRichText`
full-value entry points listed below are necessary but not sufficient. Static
inspection of the patched `ElfTools.dll` found a distinct final label path:

`ElfTools.Interfaces.Controls.RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Line`
(`0x06000A0F`) invokes `AtG.RuntimeText.CjkWordWrapBridge::ProcessWord` once
per `StringSplitter` word. For the reported label, the bridge receives six
separate tokens rather than `become obsessed with the idea of` as one string.

The runtime text bridge now performs bounded lookahead only when its existing
`RichTextFragments` map contains a matching exact, markup-free phrase of at
least three words. It reads the actual splitter's `str`, `delimeter`,
`startIndex`, and `length` fields without changing them; on a match it emits
the configured localized phrase and advances over precisely the matched tail.
The existing rich-fragment mapping supplies `会痴迷于`; no global English-word
mapping or new concept-key mapping was added. A direct bridge regression covers
the six-word match and a near-miss that must retain the original behavior.

This path is in addition to—not a replacement for—the five complete-value
filters and generated renderer redirects. The patch build, targeted runtime and
rewriter tests, and static validation gates passed. Installation hash matching
and the default main-menu smoke passed; the smoke screenshot captured Chrome,
not the game, so no visual UI verification is claimed. No target tooltip was
opened, consistent with the requested smoke-only scope.

## 2026-08-04: obsessive-trait and deserted-village tooltip repair

### Finding

The generated runtime display map already contained the exact and fragment
bindings for both reported English strings:

- `become obsessed with the idea of`
- `All that remains, of a once-thriving community.`

Changing those bindings alone could not affect the observed cards. Static IL
analysis established that both cards bypass the older `TextFormatter::Process`
field hook and arrive at the final rich-text composition boundary instead.

The relevant common-assembly methods are:

- `AtTheGatesCommon.ns_Text.CompositeString::Append_RawTextToFormat`
  (`0x0600025D`, `StringBuilder` overload)
- `AtTheGatesCommon.ns_Text.CompositeString::Append_RawTextToFormat`
  (`0x0600025E`, `string` overload)

`ClanDesireConfig::get_DescriptionForTrait` and
`get_DescriptionForTrait2` still have return-value filtering as a focused
defense-in-depth path, but the two `CompositeString` overloads are the shared
final boundary needed for both the trait tooltip and dynamically composed
rumor text. Do not retry a map-only repair for either screenshot without
checking these two sinks first.

### Correction

`RuntimeTextRedirectPlan` now injects localization of argument zero at the two
final `CompositeString` methods:

- The `string` overload receives the replacement returned by
  `DisplayStringLocalizer.LocalizeRichText(string)`.
- The `StringBuilder` overload calls the new in-place
  `DisplayStringLocalizer.LocalizeRichText(StringBuilder)` overload, so the
  original rich-text builder identity and downstream formatting are preserved.

`ManagedMethodArgumentFilterInjector` implements this bounded argument
injection and has a dedicated rewriter regression test for both the string and
`StringBuilder` forms.

The old global production fragment ` of a` is not present. It was the source
of the earlier hybrid sentence (`All that remains,` followed by an unrelated
Chinese connector and remaining English). The runtime map keeps only exact
and village-context-specific sentence pieces, so unrelated composition paths
are no longer altered by an English article fragment.

### Static verification and installation

Static decompilation after the 2026-08-04 repair found exactly five
`LocalizeRichText` calls in `AtTheGatesCommon.dll`:

1. `TextFormatter::Process` (existing path)
2. `CompositeString::Append_RawTextToFormat(StringBuilder, ...)`
3. `CompositeString::Append_RawTextToFormat(string, ...)`
4. `ClanDesireConfig::get_DescriptionForTrait`
5. `ClanDesireConfig::get_DescriptionForTrait2`

The focused `AtG.Patch.Tests` and `AtG.RuntimeText.Tests` suites passed,
including the new explicit method-argument and `StringBuilder` cases. The
project patch build completed with 149 managed redirects and five localization
redirects. The refreshed patch was installed at `2026-08-05T00:11:23`; the
installed and built `AtG.RuntimeText.dll` SHA-256 values both equal
`4E097CE2115EF69D96C3F2051DD50DE7CA6F7D6A48405A68E55DA7C82A425C3C`.

No game process or UI black-box test was started for this session, by user
direction. Manual verification must therefore test both tooltip surfaces after
loading the installed patch.

The full solution build remains blocked by unrelated existing
`AtG.TestHarness.Tests` fake-driver implementations that do not implement
`IWindowDriver.Scroll(int, int, int)`. This task did not modify that unrelated
test-harness code; the targeted projects and the patch build script completed
successfully.

## 2026-08-05: deserted-village source-path correction

The user's later capture disproved the preceding runtime-map diagnosis. The
actual `GOODY_HUT_VILLAGE` tooltip is loaded from the stable
`Content/Config/OnMap/GoodyHuts.xml` node, whose exact source description is
`All that remains of a once-thriving community.[NEWLINE]It may still contain
useful supplies, and can be investigated by an [EXPLORER].` The visible first
draw node was the standalone, no-comma `All that remains`; the prior comma
variants only happened to localize its later suffix.

The repair retains `source/Content/Config/OnMap/GoodyHuts.original.xml` and
patches only `GOODY_HUT_VILLAGE`: the name is `废弃村落` and the full description
is `这是昔日繁荣社区的遗迹。[NEWLINE]其中可能仍有有用的物资，可由[EXPLORER]调查。`
All `All that remains` runtime exact/fragment fallbacks and their focused tests
were removed rather than layered over the source patch. The description reuses
EntryPointId `xml:source/Content/Config/OnMap/GoodyHuts.original.xml:13b5fafd5d0003f0`
with RuleId `xml-existing-translation`; its concept tag and newline are retained.

`Build-Patch.ps1` completed at `2026-08-05T12:07:00Z`; the config-node stage
took 678 ms. Runtime tests, rich-text/concept-link/font/build-report checks,
and the refreshed KnownText/Composite/TODO gates passed (12,038 entries, 15
rules). Installation refreshed successfully, and the installed `GoodyHuts.xml`
has the same SHA-256 hash as the patch output. The default main-menu smoke
passed (8.31 s to window readiness plus 4.19 s stability; no crash, settings,
or Windows error). This remains smoke-only: no fixed save, new game, or target
hover was opened, so target visual verification remains pending.

## 2026-08-06: Relationship Level border-distance punctuation variants

The Relationship Level capture exposed a final-display family not textually
equivalent to the already mapped `within N tiles` reasons:
`borders being too close (1 tile apart or less.)`. A later screenshot showed
the otherwise identical external-period form:
`borders being too close (1 tile apart or less).` The runtime localizer matches
exact final fragments. An exact SQLite catalog query for the latter returned no
mapping, which explains why the previous inner-period repair did not affect the
reported UI.

`runtime-display-strings.json` reuses RuleId `runtime-display-fragment` for
the finite family: 1 uses `tile`; 2 through 12 use `tiles`. Both punctuation
positions (`less.)` and `less).`) are registered for every value, with and
without the preceding comma. All forms become `因边界过近（相距不超过N格）。`
(or the comma-prefixed equivalent). This is a 48-entry display-only family,
not a global `border`, `close`, `tile`, or `less` replacement. The refreshed
Composite authority preserves the same rule; for the one-tile examples,
`runtime-map:PlainTextFragments:0dd7923353bdc001` is the inner-period entry
and `runtime-map:PlainTextFragments:94d49898043826cd` is the external-period
entry.

`AtG.RuntimeText.Tests` loops through all 12 values and both punctuation forms,
checking bullet/comma rich-text, standalone, and comma-prefixed display output.
The rebuild completed successfully with 336 generated plain fragments. The
runtime test, patch test suite, and all selected static gates passed; the
refreshed Composite authority contains 12,115 entries, 15 rules, and 434
runtime-map entries. The manifest-backed installation refreshed successfully.

The default main-menu smoke reached a stable game window in 8.22 seconds and
remained stable for 4.13 seconds across eight checks, with no crash, settings,
or Windows error. Per the smoke-only request, no save/new game, diplomacy
panel, Relationship Level hover, or target-tooltip black-box replay occurred;
the final target visual confirmation remains with the user.
