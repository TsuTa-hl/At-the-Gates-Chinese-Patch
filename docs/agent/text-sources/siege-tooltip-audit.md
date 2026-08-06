# Besiege Tooltip Audit

## 2026-08-05: composed first-line connectors

The screenshot residual `available on its` is emitted by the zero-extra-damage
branch of `AtTheGatesUI.ns_InGame.SelectionPanel::AddButton_Besiege`
(`MethodToken` `0x06000384`). It is not the similarly worded supply-label
entry point.

The method has 16 `ldstr` operands. Every operand is covered by an exact UI
rewrite after this repair. The first-line chain now uses these connector
operands, while leaving concepts, the calculated value, and the turn label in
their original order:

| IL offset | Source | Chinese |
| --- | --- | --- |
| 185 | ` reduces the amount of ` | `会使可用` |
| 201 | ` available on its ` | `在其所在的` |
| 217 | ` by ` | `上的数值减少` |
| 262 | ` per ` | `/` |
| 272 | `.` | `。` |

The resulting dynamic wording is equivalent to
`围攻中敌方军队会使可用补给在其所在的地格上的数值减少 1/回合。` The
reused composite rule is `il-rewrite-ui`; generated entry points are scoped to
the method token and exact IL offsets above.

## Static-test handoff

Build succeeded with the UI rewrite job uncached and 1,498 exact rewrites.
`AtG.Patch.Tests` passed the focused `Besiege tooltip maps every composed
literal` test, which rewrites the original UI assembly using all 16 operands
and checks each rewritten offset. Runtime-text, rich-text, concept-link,
generated-alias, font-budget, build-report, IL-risk, composite-catalog,
composite-text, and known-text-review checks also passed. The combined runner
was stopped only by its 60-second outer limit after emitting the final
todo-list export; that check was then rerun separately and passed before
installation.

The requested validation remains smoke-only: no new game, save load, or
Besiege tooltip UI interaction is performed.

## Install and smoke conclusion

The refreshed patch was installed through the existing manifest workflow. The
installed `AtTheGatesUI.dll` and `Content/Text/AtG.RuntimeText.tsv` SHA-256
hashes matched their patch outputs. Default main-menu smoke completed with a
ready, stable window (8 stable checks over 4.15 seconds), no crash log update,
and no crash, settings, or Windows error dialog. `IncludeNewGame` and
`NewGameAttempted` were both `False`; no black-box Besiege interaction was
performed.
