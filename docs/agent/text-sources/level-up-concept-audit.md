# Level Up Concept Audit

## 2026-08-06: unify LEVEL action displays

The screenshot residual is emitted by
`AtTheGatesCommon.ns_UI.Concepts::.cctor` (`MethodToken` `0x0600026a`,
`IL_08D4`) through the existing composed entry point
`managed-map:hardcoded-common-il-rewrite.json:0x0600026a:IL_08D4`
(`RuleId` `il-rewrite-common`). Its localized source sentence correctly keeps
the concept key, but its display label remains `[Level Up|LEVEL]`.

Catalog and exact-source searches found two action-label spellings for the
`LEVEL` key, and no others:

| Source label | Final display |
| --- | --- |
| `[Level Up|LEVEL]` | `[升级|LEVEL]` |
| `[Level-Up|LEVEL]` | `[升级|LEVEL]` |

`translations/runtime-display-strings.json` now maps both spellings through
the `ConceptDisplay` layer. The related noun labels `Level` and `Levels`
remain mapped to `等级`; this avoids conflating the action `升级` with the
level-state concept. The rich-text key `LEVEL` is unchanged.

## Static-test handoff

The patch build completed successfully and generated a runtime display map
with 43 concept-display entries. `AtG.RuntimeText.Tests` now asserts both
observed spellings render as `[升级|LEVEL]` from the generated map.

The patch, runtime-text, rich-text-tag, concept-link, generated-alias,
font-budget, build-report, IL-risk, composite-catalog, composite-text,
known-text-review, and localization-todo checks all passed. The IL-risk check
reported its existing non-fatal missing-evidence warnings only. Validation is
smoke-only: no save, new game, training screen, or target-tooltip interaction
is performed.

## Install and smoke conclusion

The refreshed patch was installed through the existing manifest workflow. The
installed `Content/Text/AtG.RuntimeText.tsv`, `AtTheGatesUI.dll`, and
`Content/Text/English.xml` SHA-256 hashes matched the patch outputs; the
installed XML header is `<english>`.

Default main-menu smoke reached a ready, stable window after 8.21 seconds and
held it for 8 stable checks over 4.12 seconds. No crash-log update, crash,
settings error, or Windows error dialog was observed. `IncludeNewGame` and
`NewGameAttempted` were both `False`; no black-box training-tooltip
interaction was performed.
