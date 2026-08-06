# Leader-trait Weight Tooltip Audit

## 2026-08-06 tokenized-template ingress correction

The observed final form `Leader 特质（随和）` disproved the assumption that a
second `Weight_LeaderTrait::ToString` source operand was missing. The Common
IL source is still the exact `Leader Trait (` prefix plus dynamic trait and
closing-parenthesis operands. The hybrid final form instead identifies a
later RichTextLabel word/chunk boundary: the pre-existing exact plain fragment
` Trait` -> ` 特质` can localize only the second word before the full dynamic
template is considered.

The repair retains the full-format fallbacks and adds only two exact
intermediate forms, not a global `Leader` or `Trait` replacement:

- `Leader Trait` -> `领袖特质`, entry point
  `runtime-map:PlainText:cd5d0a56aa59a818`, rule `runtime-display-plain`.
- `Leader 特质` -> `领袖特质`, entry point
  `runtime-map:PlainText:f2ecf552fa5dc74b`, rule `runtime-display-plain`.
- `Leader Trait ({arg:0})` and `Leader 特质（{arg:0}）` continue through
  `runtime-map:Templates:cc458ab18efb0749` and
  `runtime-map:Templates:b980e5404127c4f4`, both under
  `runtime-display-template`.

`RichTextLabel/TextChunkProcessor::ProcessChunk_Normal_Line` reaches the CJK
bridge one splitter word at a time. The bridge now indexes only safe,
configured full templates and performs bounded exact lookahead, so the three
word sequence `Leader` / `Trait` / `（随和）` can use the same template as an
unsplit label. The focused regression also proves that the mixed second-word
form works and that the near miss `Leader Traits (随和)` is left unchanged.

The repair build passed the runtime-localizer and managed-rewrite tests, all
static text/composite/rich-text/concept/font/report gates, and a refresh of
the generated source and Composite catalogs (19,563 source occurrences;
12,091 Composite entries; 15 rules; 410 runtime-map entries). The refreshed
installation's runtime DLL and TSV hashes match the build artifacts. The
default main-menu smoke reached a stable game window in 8.22 seconds plus
4.13 seconds of stability without a crash, settings error, or Windows error.
No save, new game, diplomacy screen, or Leader-tooltip black-box replay was
performed; the user must visually verify the target tooltip.

## 2026-08-05 mixed-format runtime fallback correction

The renewed report identifies the residual final form as
`Leader 特质（随和）`, not the original `Leader Trait (随和)`. Static inspection
confirms that the direct `Weight_LeaderTrait::ToString` source operands remain
rewritten to `领袖特质（` and `）`; therefore the mixed string is a distinct
post-source display fallback (an inference from the observed final format),
not evidence that the exact Common rewrite was removed.

The runtime map now includes a second, equally narrow template:

`Leader 特质（{arg:0}）` -> `领袖特质（{arg:0}）`

It complements the existing fully English template and preserves the dynamic
trait argument and full-width punctuation. It does not add a global `Leader`,
`Trait`, or punctuation replacement. The generated TSV contains both templates,
and `AtG.RuntimeText.Tests` asserts that both `Leader Trait (随和)` and the
observed mixed form resolve to `领袖特质（随和）`.

The full package validation passed: runtime and managed-rewrite tests, text
and concept checks, refreshed Composite/KnownText/TODO checks, and the dynamic
build report (149 redirects, two templates). Installed UI/runtime DLL hashes
match the new patch artifacts. The default main-menu smoke passed in 8.27
seconds plus 4.17 seconds of stability, with no crash or settings/Windows
error. Its capture was the foreground Chrome window, not the game; no
diplomacy or Leader-tooltip black-box replay was performed by request.

## 2026-08-05 scoped-template smoke result

The repair now registers the full dynamic final-display template
`Leader Trait ({arg:0})` -> `领袖特质（{arg:0}）` under
`runtime-map:Templates`, rule `runtime-display-template`. It preserves the
trait argument and localizes both parentheses. The original exact Common IL
rewrite remains in place as the direct path; the template covers the observed
runtime fallback path that had left `Leader` visible.

The repaired build passed its focused runtime-localizer and managed-rewrite
regressions, the composite and known-text catalog checks, rich-text and
concept-link validation, aliases, font budget, and the updated runtime-report
gate. The generated DynamicCjk report records 149 redirects and exactly one
runtime display template. The installation refresh completed, and the
installed `AtG.RuntimeText.dll` SHA-256 matched the patch artifact.

The default `Test-GameLaunch.ps1` smoke passed: the game window was ready in
8.28 seconds, remained stable for eight checks over 4.18 seconds, and showed
no crash log update, crash dialog, settings error, or Windows error. It did
not create or load a game (`IncludeNewGame=False`, `NewGameAttempted=False`).
The harness screenshot captured the foreground Chrome window instead of the
game, so it is not visual evidence for either the main menu or the target
diplomacy tooltip. No target-UI replay was performed because this task is
explicitly smoke-only and excludes black-box coverage.

## 2026-08-05 runtime fallback failure

The user-reported screenshot disproves the earlier claim that the scoped IL
rewrite alone fixed the visible tooltip.  The patched and installed
`Weight_LeaderTrait::ToString` operands are `领袖特质（` and `）`, but the final
display path can still receive the original dynamic format.

The first runtime fallback attempt registered only `Leader Trait (` under
`runtime-map:PlainTextFragments` (`runtime-display-fragment`).  The generated
map localized `Leader Trait (随和)` to `领袖特质（随和)`: the dynamic value was
preserved, but the closing parenthesis remained half-width.  The focused
`AtG.RuntimeText.Tests` session failed on that exact expected/actual result;
no game UI was launched.  The next repair must use a scoped template that
preserves the dynamic argument and owns both parentheses, rather than
independent word or punctuation fragments.

After adding the scoped template, the composite catalog generated 381
runtime-map entries, but `Test-CompositeTextCatalog.ps1` still expected the
old fixed count of 380. This was a test-maintenance failure after successful
catalog generation, not a localization mismatch; update the assertion to
derive the count from `runtime-display-strings.json` before retrying it.

The retried composite gate then exposed a second stale category list in its
CSV-resolution assertion: it did not recognize `Templates` as a
runtime-display-map definition. The catalog and generated template remained
valid; extend that source enumeration before the next retry.

The subsequent `Test-RuntimeBuildReport.ps1` gate also failed before any game
launch: the current DynamicCjk report has 149 redirects and one runtime
template, while the test still asserted the former 145 redirects and zero
templates. Inspect the report and revise only those stale, now-explicit
invariants before retrying the report gate.

## 2026-08-05 smoke-only repair

The diplomacy leverage tooltip reported in the screenshot is composed by
`AtTheGatesCommon.ns_Config.Weight_LeaderTrait::ToString`. Its single source
occurrence builds `Leader Trait (` at `0x06000c08`, IL offset 8, then appends a
dynamic trait value and `)` at IL offset 33. The existing `[Leader Trait|LEADER-TRAIT]`
concept mapping is already localized; this separate `ToString` prefix was the
remaining visible English.

`hardcoded-common-il-rewrite.json` now applies only these exact display
operands:

- `Leader Trait (` -> `领袖特质（`
- `)` -> `）`

The associated Composite entries are
`managed-map:hardcoded-common-il-rewrite.json:0x06000c08:IL_0008` and
`managed-map:hardcoded-common-il-rewrite.json:0x06000c08:IL_0021`, both using
`il-rewrite-common`. This preserves the dynamic trait argument and its concept
markup, yielding the final display `领袖特质（随机）` without a global `Leader` or
`Trait` replacement.

The focused `AtG.Patch.Tests` regression rewrote the original Common DLL and
verified exactly these two offsets; it passed with no game process launched.
The task remains smoke-only: refresh the known-text catalog, build, install,
and run the main-menu smoke, but do not run the diplomacy UI as a black-box
scenario.

The source catalog was refreshed on 2026-08-05 after the rewrite-map change
(19,505 occurrences). `Test-CompositeTextCatalog.ps1` then passed with 12,043
entries and 15 rules; both scoped managed-map entries resolve through
`il-rewrite-common`.

`Build-Patch.ps1` completed successfully after the game process had exited.
The Common managed rewrite was rebuilt (945 scoped operations), and the build
report retained `DynamicCjk`, 149 runtime redirects, 46 runtime plain-text
entries, and 294 runtime fragments. An attempted `tools\\Test-Patch.ps1`
verification did not run because that script is absent from this repository;
this is a command-discovery limitation, not a patch-test failure. The next
static check must use the repository's actual `AtG.Patch.Tests` entry point.

The actual Release test entry points were run afterward. `AtG.Patch.Tests`
passed, including the focused `Leader-trait tooltip prefix preserves its
dynamic value` rewrite regression; `AtG.RuntimeText.Tests` also passed,
including the deserted-village and diplomacy-tooltip regressions. NuGet
vulnerability-feed lookups emitted `NU1900` because the public feed index was
unavailable, but no package restore or test execution failed.

Installation refreshed the manifest-backed patch at
`E:\\steam\\steamapps\\common\\Jon Shafer's At the Gates` without error. The
default `Test-GameLaunch.ps1` main-menu smoke then passed: the window was ready
after 12.91 seconds, remained stable for eight checks (4.16 seconds), did not
enter a new game, and reported no updated crash log, crash dialog, settings
error, or Windows error. The captured main-menu screenshot was visually
checked and shows the Chinese menu labels. No diplomacy or leader-detail
black-box scenario was run by request, so the repaired final tooltip remains
covered by the exact managed-rewrite regression rather than a target-UI replay.
