# XML, Managed Patching, and Rich Text

Use exact source evidence for XML, UI/Common/Game/ElfTools assemblies, and
runtime display maps.

## XML and Config

- Preserve stable IDs and XPath/node identity.
- Keep raw runtime tokens intact; do not turn `[FARMER:S]` or `[TIMBER]` into a
  concept link unless the source already models it as one.
- Only change the display portion of `[display|CONCEPT-KEY]` links. Preserve
  the key, color, hotkey, placeholder, and recursion structure.

## Managed Assemblies

- Prefer `MethodToken + ILOffset + Original` UI IL rewrites.
- A fallback byte or offset patch needs an exact original-byte check and a
  targeted regression. Never use a broad text search as an offset proof.
- `#US` heap patches cannot expand an entry. They must fail instead of padding
  or overwriting adjacent metadata.
- Common/Game/ElfTools edits are display-only and narrow by default. Read
  `../crash-risks.md` before changing lifecycle, settings, concepts, dates, or
  behavior-adjacent text.

## Composition

For a dynamic phrase, query `translations/composite-text-rules.json` directly
by `EntryPointId` and `RuleId`. Reuse an existing Rule ID when it covers the
same final display boundary. User review output is not AI input.
Do not reintroduce word-level `and/from/or/a` patches where a complete template
or final-display rule is available.

### Notification composition

Player-visible floating notifications are assembled in
`AtTheGatesUI.ns_Notifications.Notification::BuildText_Summary` and
`AppendDetails`, with seasonal weather notifications composed by
`NotificationtMgr::CheckFor_Weather`. Localize only complete display fragments
at their exact `MethodToken + ILOffset + Original` operands. Do not rewrite
notification type keys, comparison values, runtime placeholders, interface
object identifiers, audio paths, or unsupported-notification diagnostics.

`tools/Test-NotificationCompositionLocalization.ps1` audits every English
literal at those three display boundaries, verifies the documented exclusions,
and confirms each required mapping is present in the patched UI assembly.
`Build-Patch.ps1` runs this gate against staging output before atomically
replacing `patch/`.

Some notification operands are runtime resource identifiers rather than final
text (for example `[STONE_LARGE]`). `DisplayStringLocalizer` may render these
only through the allow-listed `BareTags` section of
`translations/runtime-display-strings.json`; it must not globally translate
unknown bracketed tokens, rich-text tags, or other engine identifiers. Keep
the resource entries synchronized with the `DEPOSIT_*` IDs in
`source/Content/Config/OnMap/Deposits.original.xml`, including all size
variants, and cover the parity with a runtime-display regression.

### Concept Tooltip Registrations

`AtTheGatesCommon.ns_UI.Concepts::.cctor` (method token `0x0600026a`) is the
canonical source for concept tooltip registration. It passes `key`, `label`,
and `description` to `Concepts.c` (`0x0600026b`); the final rich display then
flows through `TextFormatter::Process` and the runtime display localizer.

Use `ConceptTooltipCatalog` / `Invoke-AtGPatchCli.ps1 -Command
concept-tooltips` before editing this surface. The Steam source currently has
111 unique registrations. `concept-key-translations.json` covers the 109
interactive link-label keys, while `DEFEND`, `ENEMY`, `FOOD`, and `FRIEND` are
registration-only keys; `DEFENSE` and `STORED-TURN` are link-only aliases.
This count difference is intentional and must be asserted, not papered over.

Descriptions may be direct literals, `String.Concat` compositions (including
the dynamic Social icon), or an XML text-key reference (`FOREST`). Preserve
that composition exactly. Patch complete display segments with the registration
method token and IL offset, then run `Test-ConceptTooltipLocalization.ps1`.
It verifies source and patch registration parity and rejects residual English
outside the documented product-title exception.

## Recent Exact Evidence

- The `TRAIT_Miserable` contextual mood tooltip uses two independently scoped
  display paths: `ATGUnit.RecalcMood` supplies the default-mood composition,
  while `GAME.BuildDescription_Mood` supplies the clan-to-mood connector.
  Retain the existing `runtime-display-template` composition rule for the
  former and localize the latter only at method `0x06001731`, IL offset 285.
  The `SYI-ITT` fixed-save regression is the required evidence for either path.
